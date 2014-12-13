//
//  NSMutableDictionary+OMHDataPoint.h
//  OMHClient
//
//  Created by Charles Forkish on 12/13/14.
//  Copyright (c) 2014 Open mHealth. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NSMutableDictionary OMHDataPoint;
typedef NSMutableDictionary OMHHeader;
typedef NSMutableDictionary OMHSchemaID;
typedef NSMutableDictionary OMHAcquisitionProvenance;

@interface NSMutableDictionary (OMHDataPoint)

+ (instancetype)templateDataPoint;

@property (nonatomic, copy) OMHHeader *header;
@property (nonatomic, copy) NSDictionary *body;

@property (nonatomic, copy) NSString *headerID;
@property (nonatomic, copy) NSDate *creationDateTime;
@property (nonatomic, copy) OMHSchemaID *schemaID;
@property (nonatomic, copy) OMHAcquisitionProvenance *acquisitionProvenance;

@property (nonatomic, copy) NSString *schemaNamespace;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *version;


/**
 *  http://www.openmhealth.org/developers/schemas/#header
 */

typedef enum {
    OMHAcquisitionProvenanceModalitySensed,
    OMHAcquisitionProvenanceModalitySelfReported,
    OMHAcquisitionProvenanceModalityUnknown
} OMHAcquisitionProvenanceModality;

@property (nonatomic, copy) NSString *sourceName;
@property (nonatomic, copy) NSDate *sourceCreationDateTime;
@property (nonatomic) OMHAcquisitionProvenanceModality modality;



@end
