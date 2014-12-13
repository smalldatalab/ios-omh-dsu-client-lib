//
//  OMHDataPoint.h
//  OMHClient
//
//  Created by Charles Forkish on 12/12/14.
//  Copyright (c) 2014 Open mHealth. All rights reserved.
//

#import <Foundation/Foundation.h>

@class OMHHeader;
@class OMHSchemaID;
@class OMHAcquisitionProvenance;

/**
 *  http://www.openmhealth.org/developers/schemas/#data-point
 */
@interface OMHDataPoint : NSMutableDictionary

+ (instancetype)templateDataPoint;

@property (nonatomic, copy) OMHHeader *header;
@property (nonatomic, copy) NSDictionary *body;

// helpers
+ (NSString *)uuidString;
+ (NSString *)stringFromDate:(NSDate *)date;
+ (NSDate *)dateFromString:(NSString *)string;

@end


/**
 *  http://www.openmhealth.org/developers/schemas/#header
 */
@interface OMHHeader : NSMutableDictionary

+ (instancetype)templateHeader;

@property (nonatomic, copy) NSString *headerID;
@property (nonatomic, copy) NSDate *creationDateTime;
@property (nonatomic, copy) OMHSchemaID *schemaID;
@property (nonatomic, copy) OMHAcquisitionProvenance *acquisitionProvenance;

@end


/**
 *  http://www.openmhealth.org/developers/schemas/#schema-id
 */
@interface OMHSchemaID : NSMutableDictionary

+ (instancetype)templateSchemaID;

@property (nonatomic, copy) NSString *schemaNamespace;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *version;

@end


/**
 *  http://www.openmhealth.org/developers/schemas/#header
 */

typedef enum {
    OMHAcquisitionProvenanceModalitySensed,
    OMHAcquisitionProvenanceModalitySelfReported
} OMHAcquisitionProvenanceModality;

@interface OMHAcquisitionProvenance : NSMutableDictionary

+ (instancetype)templateAcquisitionProvenance;

@property (nonatomic, copy) NSString *sourceName;
@property (nonatomic, copy) NSDate *sourceCreationDateTime;
@property (nonatomic) OMHAcquisitionProvenanceModality modality;

@end