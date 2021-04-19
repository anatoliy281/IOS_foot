//
//  Header.h
//  SceneDepthPointCloud
//
//  Created by Анатолий Чернов on 15.04.2021.
//  Copyright © 2021 Apple. All rights reserved.
//

#ifndef Header_h
#define Header_h

#include "MyMeshData.h"

float getValue(const struct MyMeshData* md, int i) {
    return md->heights[i];
}


#endif /* Header_h */
