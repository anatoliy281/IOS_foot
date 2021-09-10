#include "func.hpp"

#include "ShaderTypes.h"

#include <CGAL/Triangulation_data_structure_3.h>
#include <iostream>
#include <cassert>
#include <vector>

using Tds = CGAL::Triangulation_data_structure_3<>;
using size_type = Tds::size_type;
using Cell_handle = Tds::Cell_handle;
using Vertex_handle = Tds::Vertex_handle;

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

	for (int i=0; i < count; ++i) {
		const auto p = contents[i];
		std::cout << "(" << p.position.x
						 << p.position.y
						 << p.position.z
				  << ")\n";
	}
}

