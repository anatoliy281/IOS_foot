#ifndef BufferPreprocessor_hpp
#define BufferPreprocessor_hpp

#include <CGAL/Exact_predicates_inexact_constructions_kernel.h>
#include <CGAL/Point_set_3.h>

#include "mtlpp.hpp"
#include <utility>
#include <vector>

using Kernel = CGAL::Exact_predicates_inexact_constructions_kernel;
using FT = Kernel::FT;
using Point3 = Kernel::Point_3;
using Vector3 = Kernel::Vector_3;
using PointSet = std::vector<Point3>;

class BufferPreprocessor {

private:
	
	template <typename T>
	std::pair<T*,int> returnPointerAndCount(mtlpp::Buffer buffer) {
		const auto contents = static_cast<T*>( buffer.GetContents() );
		const auto count = static_cast<int>(buffer.GetLength() / sizeof(T));
		
		return std::make_pair(contents, count);
	}
	
	void simplifyPointCloud(PointSet& points);
	
public:
	BufferPreprocessor();
	~BufferPreprocessor();
	
	void newPortion(mtlpp::Buffer points);
	
	int triangulate(mtlpp::Buffer pointBuffer,
					 mtlpp::Buffer indexBuffer);

private:
	int pointBufferSize {0};
	int indexBufferSize {0};
	int capacity {3000};
	PointSet allPoints;
};

#endif /* BufferPreprocessor_hpp */
