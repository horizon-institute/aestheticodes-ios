//
//  DtouchMarker.h
//  aestheticodes
//
//  Created by horizon on 18/07/2013.
//  Copyright (c) 2013 horizon. All rights reserved.
//
#import <Foundation/Foundation.h>

@interface Marker : NSObject
@property NSArray* code;
@property (readonly) NSString* codeKey;
@property (readonly) int emptyRegionCount;
@property (readonly) int regionCount;
@property long occurence;
@property (readonly) NSMutableArray* nodeIndexes;

@end

long occurence;