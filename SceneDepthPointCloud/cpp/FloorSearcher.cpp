#include "FloorSearcher.hpp"
#include "BufferPreprocessor.hpp"

#include <cmath>
#include <iostream>
#include <sstream>

using namespace std;


FloorSeacher::FloorSeacher(Interval interval, weak_ptr<BufferPreprocessor> master) :
	_interval {interval},
	_master {master}
	{}

ostream& operator<<(ostream& os, const FloorSeacher& seacher) {
	
	return os << seacher.getTraceInfo();
}

// ====================== BisectionFloorSearcher ===============================

BisectionFloorSearcher::BisectionFloorSearcher(Interval interval, weak_ptr<BufferPreprocessor> master) :
	FloorSeacher {interval, master}
	{}

pair<Interval,IndexFacetVec> BisectionFloorSearcher::search(const IndexFacetVec& inIndeces) {
	auto outInterval = _interval;
	IndexFacetVec outIndeces = {};
	fillBigramm(_interval, inIndeces);
	while (outInterval[2] - outInterval[0] > epsilon) {
		const auto lowerCount {lower.size()};
		const auto higherCount {higher.size()};

		auto percentOfCount = static_cast<int>(round( 100*float(min(lowerCount,higherCount))/max(lowerCount,higherCount) ));

		_information.emplace_back( outInterval, percentOfCount, make_pair(lowerCount, higherCount) );
		
		if (percentOfCount > stopPercent) {
			break;
		}
		
		if (lowerCount < higherCount) {
			outIndeces = higher;
			outInterval[0] = outInterval[1];
		} else {
			outIndeces = lower;
			outInterval[2] = outInterval[1];
		}
		outInterval[1] = 0.5f*(outInterval[0] + outInterval[2]);
		fillBigramm(outInterval, outIndeces);
	}
	
	if (outInterval[1] - outInterval[0] > maxIntervalWidth) {	// то самое "узкое" место
		outInterval[0] = outInterval[1] - maxIntervalWidth;
		outInterval[2] = outInterval[1] + maxIntervalWidth;
		
		auto lastInfo = _information.back();
		_information.emplace_back( outInterval, lastInfo._percent, lastInfo._counts );
	}
	
	
	return make_pair(move(outInterval), move(outIndeces));
}

void BisectionFloorSearcher::fillBigramm(const Interval& interval, const IndexFacetVec& v0) {
	lower = higher = {};
	for (const auto& i: v0) {
		fillForIndex(i, interval[1]);
	}
}

void BisectionFloorSearcher::fillForIndex(size_t index, float intervalCenter) {
	const auto master = _master.lock();
	
	if (!master) {
		cerr << "Что-то пошло не так... Слуга потерял своего хозяина. ( \n";
		return;
	}
	
	
	auto facets = master->getAccesToUndefinedFacets();
	const auto yC = master->getFaceCenter(facets[index]);
	if (yC < intervalCenter) {
		lower.push_back(index);
	} else {
		higher.push_back(index);
	}
}

const string BisectionFloorSearcher::getTraceInfo() const {
	ostringstream os;
	for (const auto& info: _information) {
		os << "[ " << info._interval[0] << " " << info._interval[1] << " " << info._interval[2] << " ]" << endl;
		os << "< " << info._counts.first << " : " << info._counts.second << " >   ~" << info._percent << "%" << endl << endl;
	}
	
	return os.str();
}

// ====================== HistogramSearcher ===============================

HistogramSearcher::HistogramSearcher(Interval interval, weak_ptr<BufferPreprocessor> master, float width) :
	_width {width},
	_histroCount { static_cast<int>( ceil(interval[2] - interval[0]) / _width ) },
	FloorSeacher {interval, master} {
	
	_statistic.resize(_histroCount);
	
}


pair<Interval,IndexFacetVec> HistogramSearcher::search(const IndexFacetVec& inIndeces) {
	const auto master = _master.lock();
	
	if (!master)
		return {};
	
	auto allFaces = master->getAccesToUndefinedFacets();
	const auto minPos = _interval[0];
	for (const auto& indx: inIndeces) {
		const auto pos = master->getFaceCenter(allFaces[indx]);
		const auto i = round((pos - minPos) / _width);
		_statistic[i] += 1;
	}

	const auto c = findIntervalCenter();
	const Interval outInterval {c - _width, c, c + _width};
	
	IndexFacetVec outIndeces;
	for (const auto& indx: inIndeces) {
		const auto pos = master->getFaceCenter(allFaces[indx]);
		if (outInterval[0] <= pos && pos <= outInterval[2]) {
			outIndeces.push_back(indx);
		}
	}
	
	return {outInterval, outIndeces};
}


float HistogramSearcher::findIntervalCenter() const {
	auto maxIt = max_element(_statistic.cbegin(), _statistic.cend());
	auto i = maxIt - _statistic.cbegin();
	return interpretStatistic(i);
}

const string HistogramSearcher::getTraceInfo() const {
	ostringstream os;
	
	const auto maxCount = *max_element(_statistic.cbegin(), _statistic.cend());
	const auto histroLength {90};
	
	for (size_t i=0; i < _statistic.size(); ++i) {
		const auto x = _statistic[i];
		const auto histoColumn = string(histroLength*(x/maxCount), '=');
		os << "|" << histoColumn << " ~ " << round(1000*interpretStatistic(i)) << " (mm)" << endl;
	}
	
	return os.str();
}

	

float HistogramSearcher::interpretStatistic(size_t i) const {
	return _width*i + _interval[0];
}
