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
@protocol OMHReachabilityDelegate;

@interface OMHClient : NSObject

+ (void)setupClientWithAppGoogleClientID:(NSString *)appGooggleClientID
//                    serverGoogleClientID:(NSString *)serverGoogleClientID
                          appDSUClientID:(NSString *)appDSUClientID
                      appDSUClientSecret:(NSString *)appDSUClientSecret;

+ (instancetype)sharedClient;

+ (UIButton *)googleSignInButton;

// global properties
+ (NSString *)defaultDSUBaseURL;
+ (NSString *)DSUBaseURL;
+ (void)setDSUBaseURL:(NSString *)DSUBaseURL;
+ (NSString *)appGoogleClientID;
+ (void)setAppGoogleClientID:(NSString *)appGoogleClientID;
//+ (NSString *)serverGoogleClientID;
//+ (void)setServerGoogleClientID:(NSString *)serverGoogleClientID;
+ (NSString *)appDSUClientID;
+ (void)setAppDSUClientID:(NSString *)appDSUClientID;
+ (NSString *)appDSUClientSecret;
+ (void)setAppDSUClientSecret:(NSString *)appDSUClientSecret;
+ (NSString *)signedInUsername;
+ (void)setSignedInUsername:(NSString *)signedInUsername;


@property (nonatomic, weak) id<OMHSignInDelegate> signInDelegate;
@property (nonatomic, weak) id<OMHUploadDelegate> uploadDelegate;
@property (nonatomic, weak) id<OMHReachabilityDelegate> reachabilityDelegate;
@property (nonatomic, readonly) BOOL isSignedIn;
@property (nonatomic, readonly) BOOL isReachable;
@property (nonatomic, readonly) int pendingDataPointCount;
@property (nonatomic, assign) BOOL allowsCellularAccess;


- (BOOL)handleURL:(NSURL *)url
sourceApplication:(NSString *)sourceApplication
       annotation:(id)annotation;

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
- (void)OMHClientSignInCancelled:(OMHClient *)client;


// we need these for presenting the google+ sign in web view
- (void)presentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(void (^)(void))completion;
- (void)dismissViewControllerAnimated:(BOOL)flag completion:(void (^)(void))completion;

@end

@protocol OMHUploadDelegate
- (void)OMHClient:(OMHClient *)client didUploadDataPoint:(NSDictionary *)dataPoint;
@end

@protocol OMHReachabilityDelegate
- (void)OMHClient:(OMHClient *)client reachabilityStatusChanged:(BOOL)isReachable;
@end
