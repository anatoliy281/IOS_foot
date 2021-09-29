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
	
	faces[Foot].clear();
	faces[Floor].clear();
	
	
	cout << profiler << endl;
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
