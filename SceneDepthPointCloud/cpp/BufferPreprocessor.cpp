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

#include "func.hpp"

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

BufferPreprocessor::~BufferPreprocessor() {
	cout << "~BufferPreprocessor" << endl;
}

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
	
	
	array<float,3> yInterval {-2.f, -1.f, 0.f};		// начало поиска взято с запасом (от 0 до 2 метров)
	vector<size_t> v01, v12, v0;
	fillBigramm(yInterval, v01, v12);
	while (yInterval[2] - yInterval[0] > 0.001) {
		const auto n01 {v01.size()};
		const auto n12 {v12.size()};
		if (n01 < n12) {
			v0 = v12;
			yInterval[0] = yInterval[1];
		} else {
			v0 = v01;
			yInterval[2] = yInterval[1];
		}
		yInterval[1] = 0.5f*(yInterval[0] + yInterval[2]);
		v01 = v12 = {};
		fillBigramm(yInterval, v01, v12, v0);
	}
	profiler.measure("floor height level search");
	
	auto& footFaces {faces[Foot]};
	auto& floorFaces {faces[Floor]};
	const auto& allFaces {faces[Undefined]};
	floorFaces.clear();
	footFaces.clear();
	for (const auto& fct: allFaces) {
		const auto yC = getFaceCenter(fct);
		if ( yInterval[0] < yC && yC < yInterval[2] ) {
			floorFaces.push_back(fct);
		} else if (yC > yInterval[2]) {
			footFaces.push_back(fct);
		}
	}
	profiler.measure("facets types save");
	
	cout << profiler << endl;
}

void BufferPreprocessor::fillBigramm(const array<float,3>& interval,
									 vector<size_t>& v01,
									 vector<size_t>& v12) const {

	for (size_t i=0; i < faces.at(Undefined).size(); ++i) {
		fillForIndex(v01, v12, i, interval[1]);
	}
}

void BufferPreprocessor::fillBigramm(const array<float,3>& interval,
									 vector<size_t>& v01,
									 vector<size_t>& v12,
									 const vector<size_t>& v0) const {
	for (const auto& i: v0) {
		fillForIndex(v01, v12, i, interval[1]);
	}
}

void BufferPreprocessor::fillForIndex(std::vector<std::size_t>& v01,
									  std::vector<std::size_t>& v12,
									  std::size_t index,
									  float intervalCenter) const {
	const auto facets = faces.at(Undefined);
	const auto yC = getFaceCenter(facets[index]);
	if (yC < intervalCenter) {
		v01.push_back(index);
	} else {
		v12.push_back(index);
	}
}

float BufferPreprocessor::getFaceCenter(const Facet& facet, int comp) const {
	const auto p0 = smoothedPoints[facet[0]];
	const auto p1 = smoothedPoints[facet[1]];
	const auto p2 = smoothedPoints[facet[2]];
	
	return (p0[comp] + p1[comp] + p2[comp]) / 3;
}

int BufferPreprocessor::writeCoords(mtlpp::Buffer vertecesBuffer, bool isSmoothed) const {
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

int BufferPreprocessor::writeFaces(mtlpp::Buffer indexBuffer) const {
	Profiler profiler {"Writing faces..."};
	const auto fc = faces.at(Undefined);
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
