#include "FloorSearcher.hpp"
#include "BufferPreprocessor.hpp"

#include <cmath>
#include <iostream>

using namespace std;


FloorSeacher::FloorSeacher(Interval interval, weak_ptr<BufferPreprocessor> master) :
	_interval {interval},
	_master {master}
	{}


// -------------------- BisectionFloorSearcher --------------------

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

		auto percentOfCount = round( 100*float(min(lowerCount,higherCount))/max(lowerCount,higherCount) );
		
		cout << "[ " << outInterval[0] << " " << outInterval[1] << " " << outInterval[2] << " ]" << endl;
		cout << "< " << lowerCount << " : " << higherCount << " >   ~" << percentOfCount << "%" << endl << endl;
		
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
	auto master = _master.lock();
	
	if (!master) {
		cerr << "Что-то пошло не так... Слуга потерял своего хозяина. ( \n";
		return;
	}
	
	
	const auto facets = master->getAccesToUndefinedFacets();
	const auto yC = master->getFaceCenter(facets[index]);
	if (yC < intervalCenter) {
		lower.push_back(index);
	} else {
		higher.push_back(index);
	}
}

// -------------------- HistogramSearcher --------------------

HistogramSearcher::HistogramSearcher(Interval interval, weak_ptr<BufferPreprocessor> master) :
	FloorSeacher {interval, master}
	{}


pair<Interval,IndexFacetVec> HistogramSearcher::search(const IndexFacetVec& inIndeces) {
	// implementation needed
	return {};
}
