#ifndef BufferPreprocessor_hpp
#define BufferPreprocessor_hpp

#include <CGAL/Exact_predicates_inexact_constructions_kernel.h>
#include <CGAL/Point_set_3.h>

#include "mtlpp.hpp"

using Kernel = CGAL::Exact_predicates_inexact_constructions_kernel;
using FT = Kernel::FT;
using Point3 = Kernel::Point_3;
using Vector3 = Kernel::Vector_3;
using PointSet = CGAL::Point_set_3<Point3, Vector3>;

class BufferPreprocessor {

public:
	BufferPreprocessor();
	~BufferPreprocessor();
	
	void newPortion(mtlpp::Buffer points);
	
	void triangulate(mtlpp::Buffer pointBuffer,
					 mtlpp::Buffer indexBuffer) const;

private:
	int pointBufferSize {0};
	int indexBufferSize {0};
	int capacity {3000};
	PointSet points {true};
};

#endif /* BufferPreprocessor_hpp */
