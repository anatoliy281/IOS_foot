#include "BufferPreprocessor.hpp"
#include <iostream>
#include "ShaderTypes.h"

#include <CGAL/remove_outliers.h>
#include <CGAL/grid_simplify_point_set.h>
#include <CGAL/jet_smooth_point_set.h>
#include <CGAL/Advancing_front_surface_reconstruction.h>
#include <CGAL/compute_average_spacing.h>
//#include <CGAL/jet_estimate_normals.h>

#include "func.hpp"

using CGAL::grid_simplify_point_set;
using CGAL::remove_outliers;
using CGAL::advancing_front_surface_reconstruction;

using std::vector;
using std::cout;
using std::endl;
using std::tie;

using namespace std;

BufferPreprocessor::BufferPreprocessor() {
	allPoints.reserve(capacity);
	cout << "::BufferPreprocessor" << endl;
}

BufferPreprocessor::~BufferPreprocessor() {
	cout << "~BufferPreprocessor" << endl;
}

void BufferPreprocessor::newPortion(mtlpp::Buffer buffer) {
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
	
	auto itRmv = CGAL::remove_outliers<CGAL::Sequential_tag>( pointsVec, 24 );
	pointsVec.erase(itRmv, pointsVec.end());
	profiler.measure("remove outliers");

	simplifyPointCloud(pointsVec);
	profiler.measure(string("simplify(") + to_string(pointsVec.size()) + ")");


	std::copy( pointsVec.cbegin(), pointsVec.cend(), back_inserter(allPoints) );
	profiler.measure("join");
	
	simplifyPointCloud(allPoints);
	profiler.measure("simplify joined");
	
	CGAL::jet_smooth_point_set<CGAL::Sequential_tag> (allPoints, 24);
	profiler.measure("smooth");
	
	cout << profiler << endl;
}

void BufferPreprocessor::simplifyPointCloud(PointSet& points) {
	const auto pointDist = 0.002;
	points.erase(grid_simplify_point_set(points, pointDist), points.end());
}

int BufferPreprocessor::triangulate(mtlpp::Buffer indexBuffer) {
	Profiler profiler {"Triangulation"};
	using Facet = array<size_t, 3>; // Triple of indices
	vector<Facet> facets;
	
	
	advancing_front_surface_reconstruction(allPoints.cbegin(),
										   allPoints.cend(),
										   back_inserter(facets));
	profiler.measure("reconstruction");
	
	const auto facetsCount = static_cast<int>(facets.size());
	for (int i=0; i < facetsCount; ++i) {
		auto contents = returnPointerAndCount<unsigned int>(indexBuffer).first;
		const auto& facet = facets[i];
		auto tripleIndex = 3*i;
		contents[tripleIndex] 	= static_cast<unsigned int>(facet[0]);
		contents[++tripleIndex] = static_cast<unsigned int>(facet[1]);
		contents[++tripleIndex] = static_cast<unsigned int>(facet[2]);
	}
	profiler.measure("write indeces");

	cout << profiler << endl;
	
	return 3*facetsCount;
}

int BufferPreprocessor::writeVerteces(mtlpp::Buffer vertecesBuffer) {
	Profiler profiler {"Writing verteces..."};
	int count;
	ParticleUniforms* contents;
	tie(contents, count) = returnPointerAndCount<ParticleUniforms>(vertecesBuffer);
	const auto zeroColor = simd::float3();
	const auto vertecesCount = static_cast<int>(allPoints.size());
	for (int i=0; i < allPoints.size(); ++i) {
		const auto pos3 = allPoints[i];
		auto sf3 = simd::float3();
		sf3.x = pos3.x();
		sf3.y = pos3.y();
		sf3.z = pos3.z();
		contents[i%count] = ParticleUniforms {sf3, zeroColor};
	}
	profiler.measure("write verices");
	
	return vertecesCount;
}
