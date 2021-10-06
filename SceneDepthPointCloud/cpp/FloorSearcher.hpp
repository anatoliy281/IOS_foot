#ifndef FloorSearcher_hpp
#define FloorSearcher_hpp

#include <vector>
#include <array>
#include <utility>
#include <iostream>

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
	virtual const std::string getTraceInfo() const = 0;
	
};

std::ostream& operator<<(std::ostream& os, const FloorSeacher& seacher);

// ====================== BisectionFloorSearcher ===============================

class BisectionFloorSearcher : public FloorSeacher {
	
	struct SomeInfo {
		Interval _interval;
		int _percent;
		std::pair<std::size_t,std::size_t> _counts;
		
		SomeInfo(Interval interval, int percent, std::pair<std::size_t,std::size_t> counts) :
			_interval{interval},
			_percent{percent},
			_counts{counts}
			{};
	};
	
	static constexpr float epsilon {0.001f};
	static constexpr int stopPercent {10};
	
	std::vector<SomeInfo> _information;
	
	float maxIntervalWidth {0.2f};
	IndexFacetVec lower {};
	IndexFacetVec higher {};
	
public:
	
	BisectionFloorSearcher(Interval interval, std::weak_ptr<BufferPreprocessor> master);
	
	std::pair<Interval,IndexFacetVec> search(const IndexFacetVec& inIndeces) override;
	const std::string getTraceInfo() const override;
	
private:
	// interval задаёт интервал такой, что _interval[0] < _interval[2] && _interval[1] = 0.5*(_interval[0]+_interval[2])
	// lower и higher хранит номера граней такие, что высота центра каждой грани лежат в соответствующих интервалах
	// [_interval[0], _interval[1]] и [_interval[1], _interval[2]]
	// v0 задаёт начальные индексы для их дальнейшего распределения по lower и higher
	void fillBigramm(const Interval& interval, const IndexFacetVec& v0);
	
	void fillForIndex(std::size_t index, float intervalCenter);
};


// ====================== HistogramSearcher ===============================


class HistogramSearcher : public FloorSeacher {
	static constexpr float minHistroWidth = 0.001f;
	float _width;
	int _histroCount;
	std::vector<int> _statistic;
	
private:
	float inHeightUnits(std::size_t i) const;
	Interval findInterval() const;		// more precise method may be impemented here
	
public:
	HistogramSearcher(Interval interval, std::weak_ptr<BufferPreprocessor> master, float width = minHistroWidth);
	std::pair<Interval,IndexFacetVec> search(const IndexFacetVec& inIndeces) override;
	const std::string getTraceInfo() const override;
};



#endif /* FloorSearcher_hpp */
