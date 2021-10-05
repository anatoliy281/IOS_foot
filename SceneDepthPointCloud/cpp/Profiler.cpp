#include "Profiler.hpp"

#include "ShaderTypes.h"
#include "gsl/gsl.h"
#include "Perimeter.h"
#include "FacetAdaptor.h"
#include "VertexAdaptor.h"

#include <CGAL/Triangulation_data_structure_3.h>
#include <CGAL/Simple_cartesian.h>
#include <CGAL/Advancing_front_surface_reconstruction.h>
#include <iostream>
#include <cassert>
#include <vector>
#include <array>

using Tds = CGAL::Triangulation_data_structure_3<>;
using size_type = Tds::size_type;
using Cell_handle = Tds::Cell_handle;
using Vertex_handle = Tds::Vertex_handle;

using K = CGAL::Simple_cartesian<double>;
using Point = K::Point_3;
using Facet = std::array<std::size_t,3>;

using namespace std;


void showBufferCPP(mtlpp::Buffer buffer) {
	const auto contents = static_cast<ParticleUniforms*>( buffer.GetContents() );
	const auto count = buffer.GetLength() / sizeof(ParticleUniforms);

	
	gsl::span<ParticleUniforms> spanned {contents, count};
	std::for_each(spanned.begin(), spanned.end(),
				  [](const auto& p) {
		cout << "(" << p.position.x << ","
					<< p.position.y << ","
					<< p.position.z
			 << ")\n";
	});
}

Profiler::Profiler(const string& profilerCaption) : caption{profilerCaption} {
	measuredPoints.emplace_back( make_pair("", ClockType::now()) );
}

int Profiler::intervalCount() const {
	return static_cast<int>(measuredPoints.size() - 1);
}

void Profiler::measure(const string& intervalDescription) {
	measuredPoints.emplace_back( make_pair(intervalDescription, ClockType::now()) );
}

void Profiler::reset() {
	measuredPoints.clear();
	measuredPoints.emplace_back( make_pair("", ClockType::now()) );
}

string Profiler::showTimeIntervals() const {
	
	if (measuredPoints.size() < 2) {
		return caption + " (пустo)";
	}
	
	string res = caption + ":\n";
	for (int i = 1; i < measuredPoints.size(); ++i) {
		const auto interval = measuredPoints[i].second - measuredPoints[i-1].second;
		const auto& strLine = string("\t - ") + measuredPoints[i].first + ": " + to_string(interval / 1ms) + " ms\n";
		res += strLine;
	}

	return res;
}


ostream& operator<<(ostream& os, const Profiler& profiler) {
	os << profiler.showTimeIntervals();
	return os;
}

