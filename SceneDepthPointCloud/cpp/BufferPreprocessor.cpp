#include "BufferPreprocessor.hpp"
#include <iostream>
#include <algorithm>
#include "ShaderTypes.h"

#include <CGAL/remove_outliers.h>
#include <CGAL/grid_simplify_point_set.h>
#include <CGAL/pca_estimate_normals.h>
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
    using vec3 = array<double, 3>;
    using PointNormalPair = pair<Point3, Vector3>;
    static const size_t chunkMaxCount {20};
    static size_t chunkCount {0};
    static array<vector<PointNormalPair>, chunkMaxCount> framesChunks;
    static array<pair<Vector3, Vector3>, chunkMaxCount> meanParams;
    
    Profiler profiler {"New portion of points"};
    
    if ( chunkCount == chunkMaxCount ) {    // буферы снимков накоплены, производим коррекцию снимков
        // средние нормали и положения центра масс
        Vector3 meanNormInChunks;
        Vector3 meanMassCenterInChunks;
        for (const auto& pnp: meanParams) {
            meanMassCenterInChunks += pnp.first;
            meanNormInChunks += pnp.second;
        }
        meanMassCenterInChunks /= chunkMaxCount;
        meanNormInChunks /= chunkMaxCount;
        profiler.measure("mean in frames: center and normal");
        
        array<Vector3, chunkMaxCount> shifts;
        for (size_t i=0; i < chunkMaxCount; ++i) {
            const auto c = meanParams[i].first;
            Vector3 dc {c[0] - meanMassCenterInChunks[0], c[1] - meanMassCenterInChunks[1], c[2] - meanMassCenterInChunks[2]};
            Vector3 n {meanNormInChunks[0], meanNormInChunks[1], meanNormInChunks[2]};
            const auto shiftDist = CGAL::scalar_product(n, dc);
            shifts[i] = n*shiftDist;    //  корректирующий вектор определяющий сдвиг вдоль нормали
        }
        profiler.measure("shift vector per each frame");
        
        
        chunkCount = 0;
        for (auto& chunk: framesChunks) chunk.clear();
    } else {    // продолжаем накапливать буферы
        auto& chunk = framesChunks[chunkCount];
        int count;
        ParticleUniforms* contents;
        tie(contents, count) = returnPointerAndCount<ParticleUniforms>(buffer);

        for (int i=0; i < count; ++i) {
            const auto point = contents[i].position;
            if (simd_length_squared(point) != 0) {
                chunk.emplace_back(Point3(point.x, point.y, point.z), Vector3());
            }
        }
        profiler.measure("form new chunk");
        
        // вычисление ориентаций нормалей для каждой точки по ближайшим соседям
        CGAL::pca_estimate_normals<Sequential_tag>(chunk, 8,
                                                   CGAL::parameters::point_map(CGAL::First_of_pair_property_map<PointNormalPair>()).
                                                                    normal_map(CGAL::Second_of_pair_property_map<PointNormalPair>()) );
        
        // вычисление центра и средней ориентации куска данных и занесение их в массивы
        auto& cm = meanParams[chunkCount].first;   // центр масс
        auto& nm = meanParams[chunkCount].second;  // средняя нормаль
        profiler.measure("estimate normals");
        for (int i=0; i < count; ++i) {
            const auto& point = chunk[i].first;
            const auto& norm = chunk[i].second;
            
            cm += (point - CGAL::ORIGIN);
            nm += Vector3(abs(norm.x()), abs(norm.y()), abs(norm.z()));
        }
        nm /= count;
        cm /= count;
 
        profiler.measure("mean pos and norm");
        ++chunkCount;
    }

    cout << profiler << endl;
    cout << "cur chunk num: " << chunkCount << endl;
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
    function<bool(double)> f = [](double p) -> bool {
        cout << p << endl;
        return true;
    };
    jet_smooth_point_set<Sequential_tag> (smoothedPoints, 92,
                                          CGAL::parameters::neighbor_radius(0).
                                          callback(f));
    
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
	// rid off dust
	Profiler profiler {"clusterisation"};
	// clustering foot mesh...
	using VertexIdSet = set<size_t>;	// содержит индексы вершин кластера
	using FacetIdVec = vector<size_t>;	// содержит индексы граней, которые принадлежат данному кластеру
	// каждый кластер характеризуется множеством индексов вершин и набором индексов граней, которые образуют множество вершин
	using FacetsCluster = pair<VertexIdSet, FacetIdVec>;
	using Clusters = vector<FacetsCluster>;		// набор кластеров

	const auto& footFaces = faces.at(Foot);
	Clusters clusters;

	array<size_t, 4> callingNumber {0, 0, 0, 0};	// хранит информацию о кластеризации
	
	// Конструируем новый кластер по грани face и её уникальному индексу
	auto toCluster = [](const auto& face, auto faceIndex) -> FacetsCluster {
		VertexIdSet vertexIdSet {face[0], face[1], face[2]};
		FacetIdVec faceIdVec {faceIndex};
		return {vertexIdSet, faceIdVec};
	};
	
	// Объединяем кластер cluster1 и cluster2
	auto mergeClusters = [](auto& cluster1, auto& cluster2) {
		auto& vSet1 = cluster1.first;
		auto& vSet2 = cluster2.first;
		vSet1.merge(vSet2);
		
		auto& fVec1 = cluster1.second;
		auto& fVec2 = cluster2.second;
		copy(fVec2.cbegin(), fVec2.cend(), back_inserter(fVec1));
		
		//  чистим данные объединяемого кластера
		vSet2.clear();
		fVec2.clear();
	};
	
	auto clusterFace = [&callingNumber, &clusters, mergeClusters, toCluster](const auto& face) {	// кластеризуем грань face
		static size_t faceIndex {0};	// индексы граней
		// формируем кластер из одной единственной грани
		auto newCluster = toCluster(face, faceIndex);
        
        auto findCondition = [face](const auto& cluster) {    // поиск вхождения любой из вершины face в множество вершин кластера
            const auto& clSet = cluster.first;
            const auto endIt = clSet.cend();
            // количество найденных/ненайденных вершин
            short plus {0};
            short minus {0};
            for (size_t i=0; i < face.size(); ++i) {
                const auto faceIsFound = clSet.find(face[i]) != endIt;
                if ( faceIsFound ) {    // исход определяем по последней грани
                    ++plus;
                } else {
                    ++minus;
                }
                if (plus == 2 || minus == 2)
                    break;
            }
            return plus >= 2;
        };
		
		// поиск кластеров которые содержат грань face
		auto clIt = find_if(clusters.begin(), clusters.end(), findCondition);
		vector<decltype(clIt)> foundClusters;
		while (clIt != clusters.end()) {
			foundClusters.push_back(clIt++);
			clIt = find_if(clIt, clusters.end(), findCondition);
		}

		const auto clustFoundNum = foundClusters.size();
		callingNumber[clustFoundNum]++;		// отмечаем тип операции
		if (foundClusters.empty()) {	//   добавляем новый кластер к списку кластеров
			clusters.push_back(newCluster);
		} else {	// объединяем кластеры
			auto fcl = foundClusters.front();
			// вначале все кластеры имеющие общую грань
			for_each(foundClusters.cbegin() + 1, foundClusters.cend(), [&fcl, mergeClusters](const auto& cluster) {
				return mergeClusters(*fcl, *cluster);
			});
			mergeClusters( *fcl, newCluster );	//  ... и завершаем объединения добавляя саму грань
		}
		++faceIndex;
	};
	for_each(footFaces.cbegin(), footFaces.cend(), clusterFace);
	profiler.measure("make clusters");
	
	clusters.erase( remove_if(clusters.begin(), clusters.end(), [](const auto& cluster) {
		return cluster.first.empty();
	}), clusters.end() );
	profiler.measure("clear clusters");
	
	sort(clusters.begin(), clusters.end(), [](const auto& c1, const auto& c2) {
		return c1.first.size() > c2.first.size();
	});
	profiler.measure("sorting");
	

	


	const auto largestClustersFaces = clusters.front().second;
	
	auto& polishedFaces = faces[PolishedFoot];
	polishedFaces.reserve(largestClustersFaces.size());
	
	for_each(largestClustersFaces.cbegin(), largestClustersFaces.cend(), [&polishedFaces, &footFaces](const auto& faceIndex) {
		polishedFaces.push_back(footFaces[faceIndex]);
	});
	// fill holes in foot cluster
	cout << profiler << endl;
	cout << "new cluster:" << callingNumber[0] << endl
		 << "add to cluster: " << callingNumber[1] << endl
		 << "merging 2 clusers: " << callingNumber[2] << endl
		 << "merging 3 clusters: " << callingNumber[3] << endl;
	size_t c {0};
	cout << "clusters count " << clusters.size() << endl;
	for(const auto& cl : clusters) {
		cout << "cluster(" << c++ << ") vertex/face (" << cl.first.size() << " / " << cl.second.size() << ")\n";
	}
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
	if (points.empty()) {
		cout << "Not foot points to find Foot CS!!!" << endl;
		return;
	}
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
