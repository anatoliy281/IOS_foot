#include "BufferPreprocessor.hpp"
#include <iostream>
#include <algorithm>
#include "ShaderTypes.h"

#include <CGAL/remove_outliers.h>
#include <CGAL/grid_simplify_point_set.h>
#include <CGAL/jet_smooth_point_set.h>
#include <CGAL/Advancing_front_surface_reconstruction.h>
#include <CGAL/compute_average_spacing.h>
#include <CGAL/linear_least_squares_fitting_2.h>
#include <CGAL/Aff_transformation_2.h>

#include "gsl.h"

#include <CGAL/Simple_cartesian.h>
#include <CGAL/Monge_via_jet_fitting.h>


#include "Profiler.hpp"

//using Transformation = Kernel::Aff_transformation_2;

using CGAL::grid_simplify_point_set;
using CGAL::remove_outliers;
using CGAL::advancing_front_surface_reconstruction;
using CGAL::Sequential_tag;


using std::vector;
using std::cout;
using std::endl;
using std::tie;

using namespace std;

using mtlpp::Buffer;

BufferPreprocessor::BufferPreprocessor() {
	allPoints.reserve(capacity);
	allPoints.reserve(capacity);
	
	faces[Foot].reserve(2*capacity);
	faces[Floor].reserve(0.5*capacity);
	faces[Undefined].reserve(2*capacity);
	
	cout << "::BufferPreprocessor" << endl;
}

BufferPreprocessor::BufferPreprocessor(const BufferPreprocessor& bp) :
										pointBufferSize {bp.pointBufferSize},
										indexBufferSize {bp.indexBufferSize},
										capacity {bp.capacity},
										isReadyForAcceptionNewChunk {bp.isReadyForAcceptionNewChunk},
										allPoints{bp.allPoints},
										smoothedPoints {bp.smoothedPoints},
										faces {bp.faces},
										seacher {nullptr}
{}

void BufferPreprocessor::newPortion(Buffer buffer) {
	
	if (!isReadyForAcceptionNewChunk)
		return;
	
	Profiler profiler {"New portion of points"};
	int count;
	ParticleUniforms* contents;
	tie(contents, count) = returnPointerAndCount<ParticleUniforms>(buffer);

	vector<Point3> pointsVec;
	pointsVec.reserve(count);
	for (int i=0; i < count; ++i) {
		const auto point = contents[i].position;
		if (simd_length_squared(point) != 0) {
			pointsVec.emplace_back( Point3(point.x, point.y, point.z) );
		}
	}
	
	const auto poinsCount = pointsVec.size();
	if (poinsCount <= 24)
		return;
	profiler.measure(string("form point set(")
					 + to_string(poinsCount) + ")");
	
	auto itRmv = remove_outliers<Sequential_tag>(pointsVec, 24);
	pointsVec.erase(itRmv, pointsVec.end());
	profiler.measure("remove outliers");

	copy( pointsVec.cbegin(), pointsVec.cend(), back_inserter(allPoints) );
	profiler.measure("join");
	
	simplifyPointCloud(allPoints);
	profiler.measure("simplify joined");

	cout << profiler << endl;
	cout << "size: " << allPoints.size() << endl;
}

void BufferPreprocessor::simplifyPointCloud(PointVec& points) {
	const auto pointDist = 0.002;
	points.erase(grid_simplify_point_set(points, pointDist), points.end());
}

void BufferPreprocessor::triangulate() {
	Profiler profiler {"Triangulation"};
	isReadyForAcceptionNewChunk = false;
	
	smoothedPoints.clear();
	copy(allPoints.cbegin(), allPoints.cend(), back_inserter(smoothedPoints));
	profiler.measure("form smoothed array");
	jet_smooth_point_set<Sequential_tag> (smoothedPoints, 192);
	profiler.measure("smooth");
	
	const auto nBefore = smoothedPoints.size();
	simplifyPointCloud(smoothedPoints);
	const auto nAfter = smoothedPoints.size();
	profiler.measure(string("simplify(") + to_string(nBefore) + "/" + to_string(nAfter) + ")");
	
	auto& allFaces = faces[Undefined];
	allFaces.clear();
	advancing_front_surface_reconstruction( smoothedPoints.cbegin(),
										   smoothedPoints.cend(),
										   back_inserter(allFaces) );
	profiler.measure("reconstruction");

	cout << profiler << endl;
}

void BufferPreprocessor::separate() {
	Profiler profiler {"Separation"};

	Interval yInterval {-2.f, -1.f, 0.f};		// начало поиска взято с запасом (от 0 до 2 метров)
	seacher = make_unique<BisectionFloorSearcher>(yInterval, shared_from_this());

	IndexFacetVec v0;
	filterFaces(v0, 0.9f);
	profiler.measure("filter faces");

	auto result = seacher->search(v0);
	cout << "\tITERATIONS:\n" << *seacher << endl << endl;
	
	profiler.measure("floor height level search...   1");
	
	seacher = make_unique<HistogramSearcher>(result.first, shared_from_this());
	result = seacher->search(result.second);
	cout << "\tHISTOGRAM:\n" << *seacher << endl << endl;
	profiler.measure("floor height level search...   2");

	floorInterval = result.first;
	
	writeSeparatedData();
	profiler.measure("facets types save");

	cout << profiler << endl;
}

void BufferPreprocessor::polishFoot() {
	const auto step = 2;	// шак гистограммы в мм
	auto toHistCoord = [step](float x) { // преобразование в координаты гистограммы
		return static_cast<int>(round(1000.f*x/step));
	};
	
	auto fromHistCoord = [step](int n) {
		return static_cast<float>(step*n)/1000.f;
	};
	
	// Все гистограммы организованы в набор.
	// Отдельные гистограммы доступны из данного набра и хранят не скаляры, а вектора, сворачивая которые можно определять интересующие скаляры
	using IndexedNormalVec = vector<pair<size_t,float>>; // вектор (номер грани ,вклад нормали в направлении плоскости)
	using Histogram = map<int, IndexedNormalVec>;	// отдельна гистограмма - данные в k хранят вектор
	map<int,Histogram> allHistograms;	// список гистограмм
	
	// ----------------- заполнение гистограмм ---------------------
	const auto allFaces = faces.at(Undefined);
	auto faceIndex = size_t(0);
	auto createHistograms = [this, &allFaces, &allHistograms, &faceIndex, toHistCoord](const auto& face) {
//		const auto face = allFaces[faceIndex];
		// получение 2-вектора: (XYZ) -> (xz)
		const auto c = getFaceCenter(face);
		const auto p2 = Vector2(c.x(), c.z());
		
		// получение проекций a_l и a_n
		const auto a_l = CGAL::scalar_product(p2, xAxesDir);
		const auto a_n = CGAL::scalar_product(p2, zAxesDir);
		
		// вычисление номера h гистограммы и позиции заполнения k
		const auto h = toHistCoord(a_l);
		const auto k = toHistCoord(a_n);
		
		// получение вектора нормали N, вычисление компоненты вдоль плоскости Nl
		const auto normal = getFaceNormal(face);
		const auto planeNormal = Vector2(normal.x(), normal.z());
		auto& histo = allHistograms[h];
		histo[k].emplace_back( faceIndex++, sqrt(planeNormal.squared_length()) );
	};
	for_each(allFaces.cbegin(), allFaces.cend(), createHistograms);
	
//	for (Index faceIndex=0; faceIndex < allFaces.size(); ++faceIndex) {
//		const auto face = allFaces[faceIndex];
//		// получение 2-вектора: (XYZ) -> (xz)
//		const auto c = getFaceCenter(face);
//		const auto p2 = Vector2(c.x(), c.z());
//
//		// получение проекций a_l и a_n
//		const auto a_l = CGAL::scalar_product(p2, xAxesDir);
//		const auto a_n = CGAL::scalar_product(p2, zAxesDir);
//
//		// вычисление номера h гистограммы и позиции заполнения k
//		const auto h = toHistCoord(a_l);
//		const auto k = toHistCoord(a_n);
//
//		// получение вектора нормали N, вычисление компоненты вдоль плоскости Nl
//		const auto normal = getFaceNormal(face);
//		const auto planeNormal = Vector2(normal.x(), normal.z());
//		auto& histo = allHistograms[h];
//		histo[k].emplace_back( faceIndex, sqrt(planeNormal.squared_length()) );
//	}
	
	cout << "========================= HISTOGRAMS STATISTIC ============================" << endl;
	auto showBriefHisto = [](const auto& innerHistoPair) {
		const auto& key = innerHistoPair.first;
		const auto& innerHisto = innerHistoPair.second;
		cout << key << ": " << innerHisto.size() << endl;
	};
	
	for_each(allHistograms.cbegin(), allHistograms.cend(), showBriefHisto);
	
	// ----------------- заполнение контура стопы ---------------------
	
	auto seachKClosestToZero = [](const auto& innerHistoPair1, const auto& innerHistoPair2) {
		return abs(innerHistoPair1.first) < abs(innerHistoPair2.first);
	};
	
	auto accumulateStatistic = [](auto sum, auto faceindexNormalPair) {
		return sum + faceindexNormalPair.second;
	};

	auto compareStatistics = [accumulateStatistic](const auto& innerHistoPair1, const auto& innerHistoPair2) {
		
		const auto vec1 = innerHistoPair1.second;
		const auto n1 = accumulate(vec1.begin(), vec1.end(), 0.f, accumulateStatistic);
		const auto vec2 = innerHistoPair1.second;
		const auto n2 = accumulate(vec2.begin(), vec2.end(), 0.f, accumulateStatistic);
		return n1 < n2;
	};
	
	auto saveToFootContour = [this, fromHistCoord](auto h, auto k) {
		const auto x = fromHistCoord(h);
		const auto z = fromHistCoord(k);
		const auto p = z*zAxesDir + x*xAxesDir;
		const auto y = getFloorHeight();
		footContour.emplace_back(p[0], y, p[1]);
	};
	
	auto& polishedFaces = faces[PolishedFoot];
	auto copyFaces = [this, &polishedFaces, &allFaces](const auto& indexNormalPair) {
		const auto faceIndex = indexNormalPair.first;
		polishedFaces.push_back(allFaces[faceIndex]);
	};
	auto fillPolishFaces = [copyFaces](const auto& indexStatisticPair) {
		const auto& statistic = indexStatisticPair.second;
		for_each(statistic.cbegin(), statistic.cend(), copyFaces);
	};
	
	auto findDropPos = [accumulateStatistic, compareStatistics]
	(auto startInnerHistoSearchIt, auto endInnerHistoSerchIt) {
		auto innerHistoPeakIt = max_element(startInnerHistoSearchIt, endInnerHistoSerchIt, compareStatistics);
		auto peakStatistic = innerHistoPeakIt->second;
		auto amplitude = accumulate(peakStatistic.cbegin(), peakStatistic.cend(), 0.f, accumulateStatistic);
		
		return find_if(innerHistoPeakIt, endInnerHistoSerchIt,
										[percent = 0.1, amplitude, accumulateStatistic](const auto& indexVectorPair) {
			const auto& statistic = indexVectorPair.second;
			auto amp = accumulate(statistic.cbegin(), statistic.cend(), 0.f, accumulateStatistic);
			return amp/amplitude < percent;
		});
	};
	
	auto showFullHisto = [accumulateStatistic](const auto& innerHistoPair) {
		const auto& key = innerHistoPair.first;
		const auto& innerHisto = innerHistoPair.second;
		cout << key << ": ";
		for_each(innerHisto.cbegin(), innerHisto.cend(), [accumulateStatistic](const auto& indexStaticticPair) {
			const auto& statistic = indexStaticticPair.second;
			cout << accumulate(statistic.cbegin(), statistic.cend(), 0.f, accumulateStatistic)
				 << "  ";
		});
		cout << endl;
	};
	
	auto doAllWork = [fillPolishFaces, saveToFootContour, seachKClosestToZero, findDropPos](const auto& innerHistoPair) {	// перебор всех гистограмм
		auto h = innerHistoPair.first;
		const auto& innerHisto = innerHistoPair.second;
		
		// поиск "нуля" гистограммы
		auto firstPositiveCoordIt = min_element(innerHisto.cbegin(), innerHisto.cend(), seachKClosestToZero);
		
		
		auto rightPeakDropPos = findDropPos(firstPositiveCoordIt, innerHisto.cend());
		auto leftPeakDropPos = findDropPos(make_reverse_iterator(firstPositiveCoordIt), innerHisto.rend());
		
		saveToFootContour(h, leftPeakDropPos->first);
		saveToFootContour(h, rightPeakDropPos->first);
		
		for_each(make_reverse_iterator(rightPeakDropPos), leftPeakDropPos, fillPolishFaces);
		
	};
	
//	for_each(allHistograms.begin(), allHistograms.end(), showFullHisto);

}

void BufferPreprocessor::findTransformCS() {
	Profiler profiler {"find transformation"};
	vector<Point2> points;
	const auto& footFaces = faces.at(Foot);
	for (const auto& fct: footFaces) {
		const auto center = getFaceCenter(fct);
		if ( floorInterval[1] < center[PhoneCS::Y] && center[PhoneCS::Y] < floorInterval[2]) {
			points.emplace_back( center[PhoneCS::X], center[PhoneCS::Z] );
		}
	}
	profiler.measure("form data");
	Line xAxes;
	CGAL::linear_least_squares_fitting_2(points.cbegin(), points.cend(), xAxes, xzAxesOrigin, CGAL::Dimension_tag<0>());
	
	// новые оси координат
	xAxesDir = xAxes.to_vector();
	zAxesDir = xAxes.perpendicular(xzAxesOrigin).to_vector();

//	const auto csInfo = string("origin: ") + to_string(xzAxesOrigin[0]) + " " + to_string(xzAxesOrigin[1]) + "\n" +
//						"xAxes: " + to_string(xAxesDir[0]) + " " + to_string(xAxesDir[1]) + "\n" +
//						"zAxes: " + to_string(zAxesDir[0]) + " " + to_string(zAxesDir[1]);
	profiler.measure("find foot CS (origin, axes)");
	
	cout << profiler << endl;
}

float BufferPreprocessor::getFloorHeight() const {
	return floorInterval[1];
}

Vector2 BufferPreprocessor::getAxesDir(int axes) const {
	return (axes == 0)? xAxesDir: zAxesDir;
}

Point2 BufferPreprocessor::getXZAxesOrigin() const {
	return xzAxesOrigin;
}

void BufferPreprocessor::writeSeparatedData() {
	auto& footFaces {faces[Foot]};
	auto& floorFaces {faces[Floor]};
	const auto& allFaces {faces[Undefined]};
	floorFaces.clear();
	footFaces.clear();
	
	for (const auto& fct: allFaces) {
		
		if (getFacePerimeter(fct) > maxTrianglePerimeter) continue;
		
		const auto y_pos = getFaceCenter(fct)[PhoneCS::Y];
		const auto inFloorInterval = floorInterval[0] < y_pos && y_pos < floorInterval[2];
		const auto underFloor = floorInterval[0] >= y_pos;
		const auto overTheFloor = floorInterval[2] <= y_pos;
		
		
		if (overTheFloor) { // определённо нога, т.к. находимся над границей пола
			footFaces.push_back(fct);
		} else if (underFloor) {	// однозначно мусор, т.к. под полом ничего нет!
			continue;
		} else if (inFloorInterval) {	// Зона пола. Требуется анализ ориентации нормалей
			const auto normal_y = getFaceNormal(fct)[PhoneCS::Y];
			const auto maxOrientation = 0.9f;
			const auto minOrientation = 0.6f;
			if (abs(normal_y) < minOrientation)	// нормали слабо ориентированы вверх - скорее всего нога
				footFaces.push_back(fct);
			else if (abs(normal_y) > maxOrientation) // нормали ориентированны вверх - определённо пол!
				floorFaces.push_back(fct);
			
		}
	}
}

void BufferPreprocessor::filterFaces(IndexFacetVec& v0, float threshold) const {
	const auto& allFaces = faces.at(Undefined);
	for (size_t i=0; i < allFaces.size(); ++i) {
		const auto& fct = allFaces[i];
		if ( abs(getFaceNormal(fct)[PhoneCS::Y]) > threshold )
			v0.push_back(i);
	}
}

Vector3 BufferPreprocessor::getFaceNormal(const Facet& facet) const {
	const auto& p0 = smoothedPoints[facet[0]];
	const auto& p1 = smoothedPoints[facet[1]];
	const auto& p2 = smoothedPoints[facet[2]];
	const auto& n = CGAL::normal(p0, p1, p2);
	
	return n / sqrt(n.squared_length());
}



Vector3 BufferPreprocessor::getFaceCenter(const Facet& facet) const {
	const auto p0 = smoothedPoints[facet[0]] - CGAL::ORIGIN;
	const auto p1 = smoothedPoints[facet[1]] - CGAL::ORIGIN;
	const auto p2 = smoothedPoints[facet[2]] - CGAL::ORIGIN;
	
	return (p0 + p1 + p2) / 3;
}

float BufferPreprocessor::getFacePerimeter(const Facet& facet) const {
	const auto& p0 = smoothedPoints[facet[0]];
	const auto& p1 = smoothedPoints[facet[1]];
	const auto& p2 = smoothedPoints[facet[2]];
	
	const auto a = p0 - p1;
	const auto b = p1 - p2;
	const auto c = p2 - p0;
	
	return sqrt(a.squared_length()) +
			sqrt(b.squared_length()) +
			sqrt(c.squared_length());
}

int BufferPreprocessor::writeCoords(Buffer vertecesBuffer, bool isSmoothed) const {
	if (isSmoothed) {
		return writePointsCoordsToBuffer(vertecesBuffer, smoothedPoints);
	} else {
		return writePointsCoordsToBuffer(vertecesBuffer, allPoints);
	}
}

int BufferPreprocessor::writePointsCoordsToBuffer(Buffer vertecesBuffer, const PointVec& points) const {
	Profiler profiler {"Writing verteces..."};
	int count;
	ParticleUniforms* contents;
	tie(contents, count) = returnPointerAndCount<ParticleUniforms>(vertecesBuffer);
	const auto zeroColor = simd::float3();
	const auto vertecesCount = static_cast<int>(points.size());
	for (int i=0; i < points.size(); ++i) {
		const auto pos3 = points[i];
		auto sf3 = simd::float3();
		sf3.x = pos3.x();
		sf3.y = pos3.y();
		sf3.z = pos3.z();
		contents[i%count] = ParticleUniforms {sf3, zeroColor};
	}
	profiler.measure("write verices");
	
	return vertecesCount;
}

int BufferPreprocessor::writeFaces(Buffer indexBuffer, unsigned int type) const {
	
	// TODO связать буферы на этапе конструктора класса с типом type и не передавать его явным образом
	
	Profiler profiler {"Writing faces..."};
	const auto fc = faces.at(FacetType(type));
	for (size_t i=0; i < fc.size(); ++i) {
		auto contents = returnPointerAndCount<unsigned int>(indexBuffer).first;
		auto& facet = fc[i];
		auto tripleIndex = 3*i;
		contents[tripleIndex] 	= static_cast<unsigned int>(facet[0]);
		contents[++tripleIndex] = static_cast<unsigned int>(facet[1]);
		contents[++tripleIndex] = static_cast<unsigned int>(facet[2]);
	}
	
	profiler.measure("write indeces");
	
	return static_cast<int>(3*fc.size());
}


const std::vector<Facet>& BufferPreprocessor::getAccesToUndefinedFacets() const {
	return faces.at(Undefined);
}
