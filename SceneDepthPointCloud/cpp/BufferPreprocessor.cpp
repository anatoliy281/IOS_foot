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
	
	faces[Undefined].clear();
	advancing_front_surface_reconstruction( smoothedPoints.cbegin(),
										   smoothedPoints.cend(),
										   back_inserter(faces[Undefined]) );
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
	// .................................... нахождение контура...
	// Все гистограммы организованы в набор.
	// Отдельные гистограммы доступны из данного набра и хранят не скаляры, а вектора, сворачивая которые можно определять интересующие скаляры
	using Index = size_t;	// i - номер грани
	using PlaneNormalSquared = float;	// Nl - вклад нормали в направлении плоскости
	using IndexedNormalVec = vector<pair<Index,PlaneNormalSquared>>; // вектор (i,Nl)
	using Histogram = map<int, IndexedNormalVec>;	// отдельна гистограмма - данные в k хранят вектор
	map<int,Histogram> allHistograms;	// список гистограмм
	
	// заполнение набора гистограмм
	const auto allFaces = faces.at(Undefined);
	for (Index faceIndex=0; faceIndex < allFaces.size(); ++faceIndex) {
		const auto face = allFaces[faceIndex];
		// получение 2-вектора: (XYZ) -> (xz)
		const auto c = getFaceCenter(face);
		const auto p2 = Vector2(c.x(), c.z());
		
		// получение проекций a_l и a_n
		const auto a_l = CGAL::scalar_product(p2, xAxesDir);
		const auto a_n = CGAL::scalar_product(p2, zAxesDir);
		
		// вычисление номера h гистограммы и позиции заполнения k
		const auto h = static_cast<int>(1000*round(a_l / 2));
		const auto k = static_cast<int>(1000*round(a_n / 2));
		
		// получение вектора нормали N, вычисление компоненты вдоль плоскости Nl
		const auto normal = getFaceNormal(face);
		const auto planeNormal = Vector2(normal.x(), normal.z());
		auto& histo = allHistograms[h];
		histo[k].emplace_back( faceIndex, sqrt(planeNormal.squared_length()) );
	}
	
	cout << "========================= HISTOGRAMS STATISTIC ============================" << endl;
	for_each(allHistograms.cbegin(), allHistograms.cend(), [](const auto& pair) {
		const auto& key = pair.first;
		const auto& innerHisto = pair.second;
		cout << key << ": " << innerHisto.size() << endl;
	});
	
	using LeftPeak = int;
	using RightPeak = int;
	vector<pair<LeftPeak,RightPeak>> peaks(allHistograms.size());	// положения пиков гистограмм
	for_each(allHistograms.begin(), allHistograms.end(), [&peaks](auto& pair) {	// перебор всех гистограмм
		auto& innerHisto = pair.second;
		
		// поиск нуля гистограммы
		auto firstPositiveCoordIt = find_if(innerHisto.begin(), innerHisto.end(), [](const auto& pair) {
			return pair.first >= 0;
		});
		if (firstPositiveCoordIt == innerHisto.end()) {
			cout << "		" << pair.first << "		!проблемы поиска нуля гистограммы" << endl;
			return;
		}
		
		const auto rightPeak = max_element(innerHisto.begin(), innerHisto.end(), [](const auto& p1, const auto& p2) {
			return p1.second.size() < p2.second.size();
		});
		
		const auto leftPeak = max_element( make_reverse_iterator(innerHisto.begin()), innerHisto.rend(), [](const auto& p1, const auto& p2) {
			return p1.second.size() < p2.second.size();
		} );
		peaks[pair.first] = make_pair(leftPeak->first, rightPeak->first);
	});
	
	// вычисление пиков гисограмм: (hk) -> (a_l a_n) -> (xz) -> (XYZ)
	
	// сохранение контура следа стопы в (XYZ) координатах
	// (экспорт данных следа?)
	
	
	// .................................... запись граней, центры которых лежат вне контура...
	// запись вектор индексов polishedFoot и записать туда все данные с k <= K для всех h
	
}

void BufferPreprocessor::findTransformCS() {
	Profiler profiler {"find transformation"};
	vector<Point2> points;
	const auto footFaces = faces.at(Foot);
	for (const auto& fct: footFaces) {
		const auto fc = getFaceCenter(fct);
		if ( floorInterval[1] < fc[PhoneCS::Y] && fc[PhoneCS::Y] < floorInterval[2]) {
			points.emplace_back( fc[PhoneCS::X], fct[PhoneCS::Z] );
		}
	}
	profiler.measure("form data");
	Line xAxes;
	CGAL::linear_least_squares_fitting_2(points.cbegin(), points.cend(), xAxes, xAxesOrigin, CGAL::Dimension_tag<0>());
	
	// новые оси координат
	xAxesDir = xAxes.to_vector();
	zAxesDir = xAxes.perpendicular(xAxesOrigin).to_vector();
	
	profiler.measure(string("~~~~~~~~~~~~~axes direction\n") +
					 "xAxes: " + to_string(xAxesDir[0]) + " " + to_string(xAxesDir[1]) + "\n" +
					 "zAxes: " + to_string(zAxesDir[0]) + " " + to_string(zAxesDir[1]) );
	
	cout << profiler << endl;
}

float BufferPreprocessor::getFloorHeight() const {
	return floorInterval[1];
}

Vector2 BufferPreprocessor::getAxesDir(int axes) const {
	return (axes == 0)? xAxesDir: zAxesDir;
}

Point2 BufferPreprocessor::getXAxesOrigin() const {
	return xAxesOrigin;
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
			const auto normal_y = getFaceNormal(fct)[1];
			const auto maxOrientation = 0.9f;
			const auto minOrientation = 0.6f;
			if (normal_y < minOrientation)	// нормали слабо ориентированы вверх - скорее всего нога
				footFaces.push_back(fct);
			else if (normal_y > maxOrientation) // нормали ориентированны вверх - определённо пол!
				floorFaces.push_back(fct);
			
		}
	}
}

void BufferPreprocessor::filterFaces(IndexFacetVec& v0, float threshold) const {
	const auto& allFaces = faces.at(Undefined);
	for (size_t i=0; i < allFaces.size(); ++i) {
		const auto& fct = allFaces[i];
		if ( getFaceNormal(fct)[1] > threshold )
			v0.push_back(i);
	}
}

Vector3 BufferPreprocessor::getFaceNormal(const Facet& facet) const {
	const auto& p0 = smoothedPoints[facet[0]];
	const auto& p1 = smoothedPoints[facet[1]];
	const auto& p2 = smoothedPoints[facet[2]];
	
	return CGAL::normal(p0, p1, p2);
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
