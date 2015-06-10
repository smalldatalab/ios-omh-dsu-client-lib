//
//  OMHClientDSUConnector.h
//  OMHClient
//
//  Created by Charles Forkish on 12/11/14.
//  Copyright (c) 2014 Open mHealth. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol OMHSignInDelegate;
@protocol OMHUploadDelegate;

@interface OMHClient : NSObject

+ (void)setupClientWithClientID:(NSString *)clientID
                   clientSecret:(NSString *)clientSecret;

+ (instancetype)sharedClient;

// global properties
+ (NSString *)defaultDSUBaseURL;
+ (NSString *)DSUBaseURL;
+ (void)setDSUBaseURL:(NSString *)DSUBaseURL;
+ (NSString *)clientID;
+ (void)setClientID:(NSString *)clientID;
+ (NSString *)clientSecret;
+ (void)setClientSecret:(NSString *)clientSecret;
+ (NSString *)signedInUsername;
+ (void)setSignedInUsername:(NSString *)signedInUsername;


@property (nonatomic, weak) id<OMHSignInDelegate> signInDelegate;
@property (nonatomic, weak) id<OMHUploadDelegate> uploadDelegate;
@property (nonatomic, readonly) BOOL isSignedIn;
@property (nonatomic, readonly) BOOL isReachable;
@property (nonatomic, readonly) int pendingDataPointCount;
@property (nonatomic, assign) BOOL allowsCellularAccess;


- (void)signInWithUsername:(NSString *)username password:(NSString *)password;
- (void)signOut;

- (void)getRequest:(NSString *)request withParameters:(NSDictionary *)parameters
   completionBlock:(void (^)(id responseObject, NSError *error, NSInteger statusCode))block;

- (void)postRequest:(NSString *)request withParameters:(NSDictionary *)parameters
    completionBlock:(void (^)(id responseObject, NSError *error, NSInteger statusCode))block;

- (void)authenticatedGetRequest:(NSString *)request withParameters:(NSDictionary *)parameters
                completionBlock:(void (^)(id responseObject, NSError *error, NSInteger statusCode))block;

- (void)authenticatedPostRequest:(NSString *)request withParameters:(NSDictionary *)parameters
                 completionBlock:(void (^)(id responseObject, NSError *error, NSInteger statusCode))block;


- (void)submitDataPoint:(NSDictionary *)dataPoint;
- (void)submitDataPoint:(NSDictionary *)dataPoint
   withMediaAttachments:(NSArray *)mediaAttachments;

- (void)setJSONResponseSerializerRemovesNulls:(BOOL)removeNulls;
- (void)resetSessionManagers;

@end


@protocol OMHSignInDelegate<NSObject>

- (void)OMHClient:(OMHClient *)client signInFinishedWithError:(NSError *)error;

@end

@protocol OMHUploadDelegate
- (void)OMHClient:(OMHClient *)client didUploadDataPoint:(NSDictionary *)dataPoint;
@end
