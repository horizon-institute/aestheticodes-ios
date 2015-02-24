/*
 * Aestheticodes recognises a different marker scheme that allows the
 * creation of aesthetically pleasing, even beautiful, codes.
 * Copyright (C) 2015  Aestheticodes
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU Affero General Public License as published
 *     by the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     This program is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU Affero General Public License for more details.
 *
 *     You should have received a copy of the GNU Affero General Public License
 *     along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
#import "JSONModel.h"
#import "Marker.h"
#import <Foundation/Foundation.h>

@interface Experience : JSONModel
@property (nonatomic, retain) NSString* id;
@property (nonatomic, retain) NSString* name;
@property (nonatomic, retain) NSString* icon;
@property (nonatomic, retain) NSString* image;
@property (nonatomic, retain) NSString* description;
@property (nonatomic, retain) NSString* op;
@property (nonatomic, retain) NSMutableArray<Marker>* markers;
@property (nonatomic) int version;
@property (nonatomic) int minRegions;
@property (nonatomic) int maxRegions;
@property (nonatomic) int maxEmptyRegions;
@property (nonatomic) int maxRegionValue;
@property (nonatomic) int validationRegions;
@property (nonatomic) int validationRegionValue;
@property (nonatomic) int checksumModulo;
@property (nonatomic) bool embeddedChecksum;

@property (nonatomic) int minimumContourSize;
@property (nonatomic) int maximumContoursPerFrame;
@property (nonatomic, retain) NSString* thresholdBehaviour;

-(bool)isValid:(NSArray *)code withEmbeddedChecksum:(NSNumber*)embeddedChecksum reason:(NSMutableString *)reason;
-(bool)isKeyValid:(NSString*)codeKey reason:(NSMutableString*)reason;
-(Marker*)getMarker:(NSString*) codeKey;
-(NSString*)getNextUnusedMarker;
@end
