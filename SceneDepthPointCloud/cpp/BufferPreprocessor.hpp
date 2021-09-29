#ifndef BufferPreprocessor_hpp
#define BufferPreprocessor_hpp

#include <CGAL/Exact_predicates_inexact_constructions_kernel.h>
#include <CGAL/Point_set_3.h>

#include "mtlpp.hpp"
#include "ShaderTypes.h"
#include <utility>
#include <vector>
#include <map>

using Kernel = CGAL::Exact_predicates_inexact_constructions_kernel;
using FT = Kernel::FT;
using Point3 = Kernel::Point_3;
using Vector3 = Kernel::Vector_3;
using Facet = std::array<std::size_t, 3>;
using FacetMap = std::map<FacetType, std::vector<Facet>>;
using PointVec = std::vector<Point3>;

class BufferPreprocessor {

private:
	template <typename T>
	std::pair<T*,int> returnPointerAndCount(mtlpp::Buffer buffer) const {
		const auto contents = static_cast<T*>( buffer.GetContents() );
		const auto count = static_cast<int>(buffer.GetLength() / sizeof(T));
		
		return std::make_pair(contents, count);
	}
	
	void simplifyPointCloud(PointVec& points);
	int writePointsCoordsToBuffer(mtlpp::Buffer vertecesBuffer, const PointVec& points) const;
	
	// вычисляет координату comp сентра грани faset
	// comp: 0 == x, 1 == y, 2 == z
	float getFaceCenter(const Facet& faset, int comp=1) const;
	
	// interval задаёт интервал такой, что interval[0] < interval[2] && interval[1] = 0.5*(interval[0]+interval[2])
	// v01 и v12 хранит номера граней такие, что высота центра каждой грани лежат в соответствующих интервалах
	// [interval[0], interval[1]] и [interval[1], interval[2]]
	// v0 задаёт начальные индексы для их дальнейшего распределения по v01 и v12 (на начальном этапе перебираются все грани сетки => v0 пуст)
	void fillBigramm(const std::array<float,3>& interval,
					 std::vector<std::size_t>& v01,
					 std::vector<std::size_t>& v12) const;
	
	void fillBigramm(const std::array<float,3>& interval,
					 std::vector<std::size_t>& v01,
					 std::vector<std::size_t>& v12,
					 const std::vector<std::size_t>& v0) const;
	
	void fillForIndex(std::vector<std::size_t>& v01,
					  std::vector<std::size_t>& v12,
					  std::size_t index,
					  float intervalCenter) const;
	
	
public:
	BufferPreprocessor();
	~BufferPreprocessor();
	
	void newPortion(mtlpp::Buffer points);
	
	int writeCoords(mtlpp::Buffer vertecesBuffer, bool isSmoothed) const;
	int writeFaces(mtlpp::Buffer indexBuffer) const;
	
	void triangulate();
	void separate();

private:
	int pointBufferSize {0};
	int indexBufferSize {0};
	int capacity {3000};
	bool isReadyForAcceptionNewChunk {true};
	PointVec allPoints;
	PointVec smoothedPoints;
	FacetMap faces;
};

#endif /* BufferPreprocessor_hpp */
