#include "BufferPreprocessor.hpp"
#include <iostream>
#include <algorithm>
#include "ShaderTypes.h"

#include <CGAL/remove_outliers.h>
#include <CGAL/grid_simplify_point_set.h>
#include <CGAL/pca_estimate_normals.h>
#include <CGAL/jet_smooth_point_set.h>
#include <CGAL/mst_orient_normals.h>
#include <CGAL/Advancing_front_surface_reconstruction.h>
#include <CGAL/compute_average_spacing.h>
#include <CGAL/linear_least_squares_fitting_2.h>
#include <CGAL/Aff_transformation_2.h>

#include <boost/iterator/transform_iterator.hpp>

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
	    
    static const size_t chunkMaxCount {20};
    static size_t chunkCount {0};
    static array<vector<pair<Point3, Vector3>>, chunkMaxCount> framesChunks;
    static array<pair<Vector3, Vector3>, chunkMaxCount> meanParams;
    
	if (!isReadyForAcceptionNewChunk)
		return;
    
    Profiler profiler {"New portion of points"};
    
    if ( chunkCount == chunkMaxCount ) {    // буферы снимков накоплены, производим коррекцию снимков
        // средние нормали и положения центра масс

        Vector3 cMean, nMean;
        tie(cMean, nMean) = accumulate(meanParams.cbegin(), meanParams.cend(), make_pair(Vector3(), Vector3()), [this](auto res, const auto& pvp){
            res.first += pvp.first;  // центр масс
            res.second += pvp.second;           // средняя нормаль
            return res;
        });
        cMean /= chunkMaxCount;
        nMean /= chunkMaxCount;
        profiler.measure("mean in frames: center and normal");
        
        array<Vector3, chunkMaxCount> shifts;
        transform(meanParams.cbegin(), meanParams.cend(), shifts.begin(), [cMean, nMean](const auto& vvp) {
            const auto dc { vvp.first - cMean};
            const auto shiftDist = CGAL::scalar_product(nMean, dc);
            return nMean*shiftDist;    //  корректирующий вектор определяющий сдвиг вдоль нормали
        });
        profiler.measure("find shift vector per each frame");
        
        for (size_t i=0; i < chunkMaxCount; ++i) {
            auto& chunk = framesChunks[i];
            for (size_t j=0; j < chunk.size(); ++j) {
                auto& pos = chunk[j].first;
                pos -= shifts[i];
            }
        }
        profiler.measure("shift coords in each frame");
        
        PointVec joinedFrames;
//        cout << "________" << accumulate(framesChunks.cbegin(), framesChunks.cend(), 0, [](auto n, const auto& frame) {
//            return n + frame.size();
//        });
//        accumulate(framesChunks.cbegin(), framesChunks.cend(), joinedFrames, [](auto vec, const auto& frame) {
//            for (const auto& pvp: frame)
//                vec.push_back(pvp.first);
//            return vec;
//        });
        auto projectFunc = [](const auto& pvp) {
            return pvp.first;
        };
        for (const auto& chunk: framesChunks) {
            auto chunkBegin = boost::make_transform_iterator(chunk.begin(), projectFunc);
            auto chunkEnd = boost::make_transform_iterator(chunk.end(), projectFunc);
            copy(chunkBegin, chunkEnd, back_inserter(joinedFrames));
        }
        
        simplifyPointCloud(joinedFrames);
        profiler.measure(string("join frames and simpify joined (") + to_string(joinedFrames.size()) + ")");
        
        allPoints.resize(writeToAllPointsPos);
        profiler.measure("@@@resize allPoints");
        move(joinedFrames.begin(), joinedFrames.end(), back_inserter(allPoints));
        profiler.measure("@@@move to allPoints");
        size_t n1 {allPoints.size()};
        simplifyPointCloud(allPoints);
        size_t n2 {allPoints.size()};
        profiler.measure(string("@@@simpify allPoints (") + to_string(n1) + "/" + to_string(n2) + ")");
        writeToAllPointsPos = allPoints.size();
        profiler.measure("@@@save to allPoints");
        
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
                chunk.emplace_back(toPoint3(point), Vector3());
            }
        }
        profiler.measure("form new chunk");
        const auto nb_neighbors = 8;
        if (chunk.size() < nb_neighbors) {
            return;
        }
        
        // вычисление ориентаций нормалей для каждой точки по ближайшим соседям
        using PointNormalPair = pair<Point3, Vector3>;
        using pointPart = CGAL::First_of_pair_property_map<PointNormalPair>;
        using normalPart = CGAL::Second_of_pair_property_map<PointNormalPair>;
        
        const auto parameters = CGAL::parameters::point_map(pointPart()).normal_map(normalPart());
        CGAL::pca_estimate_normals<Sequential_tag>(chunk, nb_neighbors, parameters);
        auto unoriented = CGAL::mst_orient_normals(chunk, nb_neighbors, parameters);
        chunk.erase(unoriented, chunk.end());
        profiler.measure("calc normals");
        
        // вычисление центра и средней ориентации куска данных и занесение их в массивы
        auto& curParams = meanParams[chunkCount];
        curParams = accumulate(chunk.cbegin(), chunk.cend(), make_pair(Vector3(), Vector3()), [this](auto res, const auto& pvp){
            res.first += toVector3(pvp.first);  // центр масс
            res.second += pvp.second;           // средняя нормаль
            return res;
        });
        curParams.first /= chunkCount;
        curParams.second /= chunkCount;
 
        profiler.measure("mean pos and norm");
        
        auto projectFunc = [](const auto& pvp) {
            return pvp.first;
        };
        auto chunkBegin = boost::make_transform_iterator(chunk.begin(), projectFunc);
        auto chunkEnd = boost::make_transform_iterator(chunk.end(), projectFunc);
        copy(chunkBegin, chunkEnd, back_inserter(allPoints));
        
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
	const auto p0 = toVector3(smoothedPoints[facet[0]]);
    const auto p1 = toVector3(smoothedPoints[facet[1]]);
	const auto p2 = toVector3(smoothedPoints[facet[2]]);
	
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
		contents[i%count] = ParticleUniforms {toSIMD3(points[i]), zeroColor};
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


simd::float3 BufferPreprocessor::toSIMD3(const Point3& pos) const {
    simd::float3 res;
    res[0] = pos.x();
    res[1] = pos.y();
    res[2] = pos.z();
    return res;
}

simd::float3 BufferPreprocessor::toSIMD3(const Vector3& pos) const {
    simd::float3 res;
    res[0] = pos.x();
    res[1] = pos.y();
    res[2] = pos.z();
    return res;
}

Point3 BufferPreprocessor::toPoint3(const simd::float3& x) const {
    return Point3(x[0], x[1], x[2]);
}

Vector3 BufferPreprocessor::toVector3(const simd::float3& x) const {
    return Vector3(x[0], x[1], x[2]);
}

Vector3 BufferPreprocessor::toVector3(const Point3& point) const {
    return point - CGAL::ORIGIN;
}
