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

enum PhoneCS {
	X = 0, Y = 1, Z = 2
};

enum FootCS {
	x = 0, y = 1, z = 2
};

using Kernel = CGAL::Exact_predicates_inexact_constructions_kernel;
using FT = Kernel::FT;
using Point3 = Kernel::Point_3;
using Vector3 = Kernel::Vector_3;
using Line = Kernel::Line_2;
using Point2 = Kernel::Point_2;
using Vector2 = Kernel::Vector_2;

using Facet = std::array<std::size_t, 3>;
using FacetMap = std::map<FacetType, std::vector<Facet>>;
using PointVec = std::vector<Point3>;


class BufferPreprocessor : public std::enable_shared_from_this<BufferPreprocessor> {

	static constexpr float maxTrianglePerimeter {0.03};
	
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
	
	void writeSeparatedData();
	
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
	void polishFoot();
	
	// вычисляет координату comp сентра грани faset
	// comp: 0 == x, 1 == y, 2 == z
	Vector3 getFaceCenter(const Facet& facet) const;
	
	float getFacePerimeter(const Facet& facet) const;

	// вычисляет квадрат компоненты comp нормали грани facet. Нормаль предполагается нормированной.
	Vector3 getFaceNormal(const Facet& facet) const;
	
	// набор методов вычисляющих параметры преобразования СК
	void findTransformCS();
	
	float getFloorHeight() const;
	Vector2 getAxesDir(int axes) const;
	Point2 getXAxesOrigin() const;


	PointVec footContour;
	
private:
	int pointBufferSize {0};
	int indexBufferSize {0};
	int capacity {3000};
	bool isReadyForAcceptionNewChunk {true};
	
	Interval floorInterval;
	
	// задают преобразования СК
	Vector2 xAxesDir;
	Vector2 zAxesDir;
	Point2 xAxesOrigin;
	
	PointVec allPoints;
	PointVec smoothedPoints;
	FacetMap faces;
	
	std::unique_ptr<FloorSeacher> seacher {nullptr};
};

#endif /* BufferPreprocessor_hpp */
