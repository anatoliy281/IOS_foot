#ifndef BufferPreprocessor_hpp
#define BufferPreprocessor_hpp

#include <CGAL/Exact_predicates_inexact_constructions_kernel.h>
#include <CGAL/Point_set_3.h>

#include "mtlpp.hpp"
#include "ShaderTypes.h"
#include "FloorSearcher.hpp"

#include <utility>
#include <vector>
#include <map>
#include <memory>

using Kernel = CGAL::Exact_predicates_inexact_constructions_kernel;
using FT = Kernel::FT;
using Point3 = Kernel::Point_3;
using Vector3 = Kernel::Vector_3;
using Facet = std::array<std::size_t, 3>;
using FacetMap = std::map<FacetType, std::vector<Facet>>;
using PointVec = std::vector<Point3>;


class BufferPreprocessor : public std::enable_shared_from_this<BufferPreprocessor> {

private:
	template <typename T>
	std::pair<T*,int> returnPointerAndCount(mtlpp::Buffer buffer) const {
		const auto contents = static_cast<T*>( buffer.GetContents() );
		const auto count = static_cast<int>(buffer.GetLength() / sizeof(T));
		
		return std::make_pair(contents, count);
	}
	
	void simplifyPointCloud(PointVec& points);
	int writePointsCoordsToBuffer(mtlpp::Buffer vertecesBuffer, const PointVec& points) const;
	
	
	void filterFaces(IndexFacetVec& v0, float threshold) const;
	
	void writeSeparatedData(float floorHeight, float heightWidth);
	
public:
	BufferPreprocessor();
	BufferPreprocessor(const BufferPreprocessor& bp);
	BufferPreprocessor(BufferPreprocessor&& bp) = delete;
	~BufferPreprocessor() = default;
	
	void newPortion(mtlpp::Buffer points);
	
	int writeCoords(mtlpp::Buffer vertecesBuffer, bool isSmoothed) const;
	int writeFaces(mtlpp::Buffer indexBuffer, unsigned int type ) const;
	
	const std::vector<Facet>& getAccesToUndefinedFacets() const;
	
	void triangulate();
	void separate();
	
	// вычисляет координату comp сентра грани faset
	// comp: 0 == x, 1 == y, 2 == z
	float getFaceCenter(const Facet& facet, int comp=1) const;

	// вычисляет квадрат компоненты comp нормали грани facet. Нормаль предполагается нормированной.
	float getFaceNormalSquared(const Facet& facet, int comp=1) const;


private:
	int pointBufferSize {0};
	int indexBufferSize {0};
	int capacity {3000};
	bool isReadyForAcceptionNewChunk {true};
	PointVec allPoints;
	PointVec smoothedPoints;
	FacetMap faces;
	
	std::unique_ptr<FloorSeacher> seacher {nullptr};
};

#endif /* BufferPreprocessor_hpp */