#include "BufferPreprocessor.hpp"
#include <iostream>
#include <algorithm>
#include "ShaderTypes.h"

#include <CGAL/remove_outliers.h>
#include <CGAL/grid_simplify_point_set.h>
#include <CGAL/jet_smooth_point_set.h>
#include <CGAL/Advancing_front_surface_reconstruction.h>
#include <CGAL/compute_average_spacing.h>
//#include <CGAL/jet_estimate_normals.h>

#include "gsl.h"

#include "Profiler.hpp"

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

	auto floorInterval = result.first;
	
	writeSeparatedData(floorInterval);
	profiler.measure("facets types save");

	cout << profiler << endl;
}

void BufferPreprocessor::writeSeparatedData(Interval floorInterval) {
	auto& footFaces {faces[Foot]};
	auto& floorFaces {faces[Floor]};
	const auto& allFaces {faces[Undefined]};
	floorFaces.clear();
	footFaces.clear();
	
	for (const auto& fct: allFaces) {
		
		if (getFacePerimeter(fct) > maxTrianglePerimeter) continue;
		
		const auto pos = getFaceCenter(fct);
		const auto inFloorInterval = floorInterval[0] < pos && pos < floorInterval[2];
		const auto underFloor = floorInterval[0] >= pos;
		const auto overTheFloor = floorInterval[2] <= pos;
		if (inFloorInterval) {	// Зона пола. Требуется анализ ориентации нормалей
			const auto normal = getFaceNormalSquared(fct);
			const auto maxOrientation {0.9f*0.9f};
			const auto minOrientation {0.6f*0.6f};
			if (normal < minOrientation)	// нормали слабо ориентированы вверх - скорее всего нога
				footFaces.push_back(fct);
			else if (normal > maxOrientation) // нормали ориентированны вверх - определённо пол!
				floorFaces.push_back(fct);
			
		} else if (overTheFloor) // определённо нога, т.к. находимся над границей пола
			footFaces.push_back(fct);
		else if (underFloor)	// однозначно мусор, т.к. под полом ничего нет!
			continue;
	}
}

void BufferPreprocessor::filterFaces(IndexFacetVec& v0, float threshold) const {
	const auto& allFaces = faces.at(Undefined);
	const auto nsq = threshold*threshold;
	for (size_t i=0; i < allFaces.size(); ++i) {
		const auto& fct = allFaces[i];
		if ( getFaceNormalSquared(fct) > nsq )
			v0.push_back(i);
	}
}

float BufferPreprocessor::getFaceNormalSquared(const Facet& facet, int comp) const {
	const auto& p0 = smoothedPoints[facet[0]];
	const auto& p1 = smoothedPoints[facet[1]];
	const auto& p2 = smoothedPoints[facet[2]];
	
	const auto& n = CGAL::cross_product(p1 - p0, p2 - p0);
	auto lsq = n.squared_length();
	return n[comp]*n[comp] / lsq;
}



float BufferPreprocessor::getFaceCenter(const Facet& facet, int comp) const {
	const auto& p0 = smoothedPoints[facet[0]];
	const auto& p1 = smoothedPoints[facet[1]];
	const auto& p2 = smoothedPoints[facet[2]];
	
	return (p0[comp] + p1[comp] + p2[comp]) / 3;
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
