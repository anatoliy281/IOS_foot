#include "FloorSearcher.hpp"
#include "BufferPreprocessor.hpp"

#include <cmath>
#include <iostream>
#include <sstream>

#include "Profiler.hpp"

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
	
	if (outInterval[2] - outInterval[0] > maxIntervalWidth) {	// то самое "узкое" место
		outInterval[0] = outInterval[1] - 0.5*maxIntervalWidth;
		outInterval[2] = outInterval[1] + 0.5*maxIntervalWidth;
		
		auto lastInfo = _information.back();
		_information.emplace_back( outInterval, lastInfo._percent, lastInfo._counts );
	}
	
	return make_pair(move(outInterval), move(outIndeces));
}

void BisectionFloorSearcher::fillBigramm(const Interval& interval, const IndexFacetVec& v0) {
//	Profiler profiler {"Fill bigram"};
	lower.clear();
	higher.clear();
//	profiler.measure("clear low high");
	
	const auto master = _master.lock();
	if (!master) {
		cerr << "Что-то пошло не так... Слуга потерял своего хозяина. ( \n";
		return;
	}
	auto facets = master->getAccesToUndefinedFacets();
	for (const auto& index: v0) {
		const auto yC = master->getFaceCenter(facets[index]);
		if (yC < interval[1]) {
			lower.push_back(index);
		} else {
			higher.push_back(index);
		}
	}
//	profiler.measure("push low high");
//	cout << profiler << endl;
}

void BisectionFloorSearcher::fillForIndex(size_t index, float intervalCenter) {
	
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
	_histroCount { static_cast<int>( ceil((interval[2] - interval[0]) / _width) ) },
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

	const auto outInterval {findInterval()};
	IndexFacetVec outIndeces;
	for (const auto& indx: inIndeces) {
		const auto pos = master->getFaceCenter(allFaces[indx]);
		if (outInterval[0] <= pos && pos <= outInterval[2]) {
			outIndeces.push_back(indx);
		}
	}
	
	return {outInterval, outIndeces};
}


Interval HistogramSearcher::findInterval() const {
	auto maxIt = max_element(_statistic.cbegin(), _statistic.cend());
	const auto ic = maxIt - _statistic.cbegin();
	const auto center {inHeightUnits(ic)};
	
	auto zeroIt = find_if(maxIt, _statistic.cend(),
		[](int n) {
		return n == 0;
	});
	auto ib = zeroIt - _statistic.cbegin();
	const auto highEdge {inHeightUnits(ib)};
	const auto w {highEdge-center};
	
	cout << "height edge: " << highEdge << endl;
	cout << "interrval: " << center - w << " " << center << " " <<  center + w << endl;
	
	return {center - w, center, center + w};
}

const string HistogramSearcher::getTraceInfo() const {
	ostringstream os;
	
	const auto maxCount = *max_element(_statistic.cbegin(), _statistic.cend());
	const auto histroLengthPercent {100};
	
	for (size_t i=0; i < _statistic.size(); ++i) {
		const auto count = _statistic[i];
		const auto histoColumn = string( histroLengthPercent*(static_cast<float>(count)/maxCount), '=' );
		os << "|" << histoColumn << " ~ " << round(1000*inHeightUnits(i)) << " (mm) " << count << endl;
	}
	
	return os.str();
}

	

float HistogramSearcher::inHeightUnits(size_t i) const {
	return _width*i + _interval[0];
}
