#ifndef FloorSearcher_hpp
#define FloorSearcher_hpp

#include <vector>
#include <array>
#include <utility>

class BufferPreprocessor;
			
using IndexFacetVec = std::vector<std::size_t>;
using Interval = std::array<float,3>;

class FloorSeacher {
	
protected:
	Interval _interval;
	std::weak_ptr<BufferPreprocessor> _master;
	
public:
	
	FloorSeacher(Interval interval, std::weak_ptr<BufferPreprocessor> master);
	
	FloorSeacher() = delete;
	FloorSeacher(const FloorSeacher& seacher) = delete;
	FloorSeacher(FloorSeacher&& seacher) = delete;

	
	virtual ~FloorSeacher() = default;
	virtual std::pair<Interval,IndexFacetVec> search(const IndexFacetVec& inIndeces) = 0;
	
};

class BisectionFloorSearcher : public FloorSeacher {
	
	static constexpr float epsilon {0.001f};
	static constexpr int stopPercent {10};
	
	float maxIntervalWidth {0.1f};
	IndexFacetVec lower {};
	IndexFacetVec higher {};
	
public:
	
	BisectionFloorSearcher(Interval interval, std::weak_ptr<BufferPreprocessor> master);
	
	std::pair<Interval,IndexFacetVec> search(const IndexFacetVec& inIndeces) override;
	
private:
	// interval задаёт интервал такой, что _interval[0] < _interval[2] && _interval[1] = 0.5*(_interval[0]+_interval[2])
	// lower и higher хранит номера граней такие, что высота центра каждой грани лежат в соответствующих интервалах
	// [_interval[0], _interval[1]] и [_interval[1], _interval[2]]
	// v0 задаёт начальные индексы для их дальнейшего распределения по lower и higher
	void fillBigramm(const Interval& interval, const IndexFacetVec& v0);
	
	void fillForIndex(std::size_t index, float intervalCenter);
};




class HistogramSearcher : public FloorSeacher {
	
public:
	HistogramSearcher(Interval interval, std::weak_ptr<BufferPreprocessor> master);
	
	std::pair<Interval,IndexFacetVec> search(const IndexFacetVec& inIndeces) override;
};

#endif /* FloorSearcher_hpp */
