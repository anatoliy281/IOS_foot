#include "func.hpp"

#include "ShaderTypes.h"
#include "gsl/gsl.h"

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

void testCall() {
	Tds T;
	assert( T.number_of_vertices() == 0 );
	assert( T.dimension() == -2 );
	assert( T.is_valid() );
	vector<Vertex_handle> PV(7);
	PV[0] = T.insert_increase_dimension();
	assert( T.number_of_vertices() == 1 );
	assert( T.dimension() == -1 );
	assert( T.is_valid() );
	
	// each of the following insertions of vertices increases the dimension
	for ( int i=1; i<5; i++ ) {
		PV[i] = T.insert_increase_dimension(PV[0]);
		assert( T.number_of_vertices() == (size_type) i+1 );
		assert( T.dimension() == i-1 );
		assert( T.is_valid() );
	}
	assert( T.number_of_cells() == 5 );
	
	// we now have a simplex in dimension 4
	// cell incident to PV[0]
	Cell_handle c = PV[0]->cell();
	int ind;
	bool check = c->has_vertex( PV[0], ind );
	assert( check );
	
	// PV[0] is the vertex of index ind in c
	// insertion of a new vertex in the facet opposite to PV[0]
	PV[5] = T.insert_in_facet(c, ind);
	assert( T.number_of_vertices() == 6 );
	assert( T.dimension() == 3 );
	assert( T.is_valid() );
	// insertion of a new vertex in c
	PV[6] = T.insert_in_cell(c);
	assert( T.number_of_vertices() == 7 );
	assert( T.dimension() == 3 );
	assert( T.is_valid() );

	// writing file output_tds;
	cout << T;
}

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

namespace std {
	ostream&
	operator<<(ostream& os, const Facet& f) {
		os << "3 " << f[0] << " " << f[1] << " " << f[2];
		return os;
	}
}

struct Perimeter {
	
	double bound;
	Perimeter(double bound) : bound(bound) {}

	template <typename AdvancingFront, typename Cell_handle>
	double operator() (const AdvancingFront& adv,
					   Cell_handle& c,
					   const int& index) const {
		// bound == 0 is better than bound < infinity
		// as it avoids the distance computations
		if(bound == 0){
			return adv.smallest_radius_delaunay_sphere (c, index);
		}
		// If perimeter > bound, return infinity so that facet is not used
		double d  = 0;
		d = sqrt(squared_distance(c->vertex((index+1)%4)->point(),
								  c->vertex((index+2)%4)->point()));
		if(d > bound)
			return adv.infinity();
		d += sqrt(squared_distance(c->vertex((index+2)%4)->point(),
								   c->vertex((index+3)%4)->point()));
		if(d > bound)
			return adv.infinity();
		d += sqrt(squared_distance(c->vertex((index+1)%4)->point(),
								   c->vertex((index+3)%4)->point()));
		if(d > bound)
			return adv.infinity();
		// Otherwise, return usual priority value: smallest radius of
		// delaunay sphere
		return adv.smallest_radius_delaunay_sphere (c, index);
	}
};

void triangulate() {
	double per = 0;
//	double radius_ratio_bound = 5.0;
	vector<Point> points = { Point(1,4,6), Point(1,4,6), Point(4,4,4),
							 Point(1,4,3), Point(1,7,6), Point(8,4,6) };
	vector<Facet> facets;
	Perimeter perimeter(per);

	CGAL::advancing_front_surface_reconstruction(points.begin(),
											   points.end(),
											   std::back_inserter(facets));

	cout << "		Done!!!: " << points.size() << " " << facets.size() << "\n";
	copy(points.begin(), points.end(), ostream_iterator<Point>(cout, "\n"));
	copy(facets.begin(), facets.end(), ostream_iterator<Facet>(cout, "\n"));
}
