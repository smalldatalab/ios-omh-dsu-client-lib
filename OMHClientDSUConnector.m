//
//  OMHClientLibrary.m
//  OMHClient
//
//  Created by Charles Forkish on 12/11/14.
//  Copyright (c) 2014 Open mHealth. All rights reserved.
//

#import "OMHClientDSUConnector.h"
#import "AFHTTPSessionManager.h"
#import "AFNetworkActivityIndicatorManager.h"
#import "OMHDataPoint.h"
#import "OMHApplication.h"

#import <GooglePlus/GooglePlus.h>
#import <GoogleOpenSource/GoogleOpenSource.h>

#ifdef OMHDEBUG
#   define OMHLog(fmt, ...) NSLog((@"%s " fmt), __PRETTY_FUNCTION__, ##__VA_ARGS__)
#else
#   define OMHLog(...)
#endif

NSString * const kDefaultDSUBaseURL = @"https://ohmage-omh.smalldata.io/dsu";

NSString * const kDSUBaseURLKey = @"DSUBaseURLKey";
NSString * const kAppGoogleClientIDKey = @"AppGoogleClientID";
NSString * const kServerGoogleClientIDKey = @"ServerGoogleClientID";
NSString * const kAppDSUClientIDKey = @"AppDSUClientID";
NSString * const kAppDSUClientSecretKey = @"AppDSUClientSecret";
NSString * const kSignedInUsernameKey = @"SignedInUsername";

static OMHClient *_sharedClient = nil;
static GPPSignIn *_gppSignIn = nil;


@interface OMHClient () <GPPSignInDelegate, UIWebViewDelegate>

@property (nonatomic, strong) AFHTTPSessionManager *httpSessionManager;
@property (nonatomic, strong) AFHTTPSessionManager *backgroundSessionManager;

@property (nonatomic, strong) NSString *userPassword;
@property (nonatomic, strong) NSString *dsuAccessToken;
@property (nonatomic, strong) NSString *dsuRefreshToken;
@property (nonatomic, strong) NSDate *accessTokenDate;
@property (nonatomic, assign) NSTimeInterval accessTokenValidDuration;

@property (nonatomic, strong) NSMutableArray *pendingDataPoints;
@property (nonatomic, strong) NSMutableArray *pendingRichMediaDataPoints;

@property (nonatomic, assign) BOOL isAuthenticated;
@property (atomic, assign) BOOL isAuthenticating;
@property (nonatomic, strong) NSMutableArray *authRefreshCompletionBlocks;

@property (nonatomic, weak) UIActivityIndicatorView *activityIndicator;

@property (strong) NSTimer *saveTimer;

@end

@implementation OMHClient

+ (void)setupClientWithAppGoogleClientID:(NSString *)appGooggleClientID
                    serverGoogleClientID:(NSString *)serverGoogleClientID
                          appDSUClientID:(NSString *)appDSUClientID
                      appDSUClientSecret:(NSString *)appDSUClientSecret
{
    [self setAppGoogleClientID:appGooggleClientID];
    [self setServerGoogleClientID:serverGoogleClientID];
    [self setAppDSUClientID:appDSUClientID];
    [self setAppDSUClientSecret:appDSUClientSecret];
}

+ (instancetype)sharedClient
{
    if (_sharedClient == nil) {
        OMHClient *client = nil;
        NSString *signedInUsername = [self signedInUsername];
        
        if (signedInUsername != nil) {
            NSData *encodedClient = [self encodedClientForUsername:signedInUsername];
            
            if (encodedClient != nil) {
                client = (OMHClient *)[NSKeyedUnarchiver unarchiveObjectWithData:encodedClient];
            }
        }
        
        if (client == nil) {
            client = [[self alloc] initPrivate];
        }
        
        _sharedClient = client;
    }
    
    return _sharedClient;
}

+ (void)releaseShared
{
    _sharedClient = nil;
    _gppSignIn = nil;
}

+ (NSString *)archiveKeyForUsername:(NSString *)username
{
    return [NSString stringWithFormat:@"OMHClient_%@", username];
}

+ (NSData *)encodedClientForUsername:(NSString *)username
{
    OMHLog(@"unarchiving client for username: %@", username);
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [defaults objectForKey:[self archiveKeyForUsername:username]];
}

- (instancetype)init
{
    @throw [NSException exceptionWithName:@"Singleton"
                                   reason:@"Use +[OMHClient sharedClient]"
                                 userInfo:nil];
    return nil;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)commonInit
{
    OMHLog(@"common init");
    [self.httpSessionManager.reachabilityManager startMonitoring];
    [OMHClient gppSignIn].delegate = self;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleOpenGoogleAuthNotification:)
                                                 name:ApplicationOpenGoogleAuthNotification
                                               object:nil];
}

- (instancetype)initPrivate
{
    self = [super init];
    if (self) {
        
        self.pendingDataPoints = [NSMutableArray array];
        [self commonInit];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super init];
    if (self != nil) {
        _userPassword = [decoder decodeObjectForKey:@"client.userPassword"];
        _dsuAccessToken = [decoder decodeObjectForKey:@"client.dsuAccessToken"];
        _dsuRefreshToken = [decoder decodeObjectForKey:@"client.dsuRefreshToken"];
        _pendingDataPoints = [decoder decodeObjectForKey:@"client.pendingDataPoints"];
        _pendingRichMediaDataPoints = [decoder decodeObjectForKey:@"client.pendingRichMediaDataPoints"];
        if (_pendingRichMediaDataPoints == nil) _pendingRichMediaDataPoints = [NSMutableArray array];
        _accessTokenDate = [decoder decodeObjectForKey:@"client.accessTokenDate"];
        _accessTokenValidDuration = [decoder decodeDoubleForKey:@"client.accessTokenValidDuration"];
        _allowsCellularAccess = [decoder decodeBoolForKey:@"client.allowsCellularAccess"];
        [self commonInit];
    }
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeObject:self.userPassword forKey:@"client.userPassword"];
    [encoder encodeObject:self.dsuAccessToken forKey:@"client.dsuAccessToken"];
    [encoder encodeObject:self.dsuRefreshToken forKey:@"client.dsuRefreshToken"];
    [encoder encodeObject:self.pendingDataPoints forKey:@"client.pendingDataPoints"];
    [encoder encodeObject:self.pendingRichMediaDataPoints forKey:@"client.pendingRichMediaDataPoints"];
    [encoder encodeObject:self.accessTokenDate forKey:@"client.accessTokenDate"];
    [encoder encodeDouble:self.accessTokenValidDuration forKey:@"client.accessTokenValidDuration"];
    [encoder encodeBool:self.allowsCellularAccess forKey:@"client.allowsCellularAccess"];
}

- (void)unarchivePendingDataPointsForUsername:(NSString *)username
{
    NSData *encodedClient = [OMHClient encodedClientForUsername:username];
    if (encodedClient != nil) {
        OMHClient *archivedClient = (OMHClient *)[NSKeyedUnarchiver unarchiveObjectWithData:encodedClient];
        if (archivedClient != nil) {
            self.pendingDataPoints = archivedClient.pendingDataPoints;
            self.pendingRichMediaDataPoints = archivedClient.pendingRichMediaDataPoints;
            OMHLog(@"Unarchived %@ data points and %@ rich data points for username: %@",
                   [@(self.pendingDataPoints.count) stringValue],
                   [@(self.pendingRichMediaDataPoints.count) stringValue],
                   username);
        }
    }
}

- (void)deferredSave
{
    [self.saveTimer invalidate];
    self.saveTimer = nil;
    
    NSString *signedInUsername = [OMHClient signedInUsername];
    if (signedInUsername == nil) {
        OMHLog(@"attempting to save client with no signed-in user");
        return;
    }
    
    NSData *encodedClient = [NSKeyedArchiver archivedDataWithRootObject:self];
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setObject:encodedClient forKey:[OMHClient archiveKeyForUsername:signedInUsername]];
    [userDefaults synchronize];
}

- (void)saveClientState
{
    OMHLog(@"saving client state, pending: %d, timer: %d", (int)self.pendingDataPoints.count, self.saveTimer != nil);
    if (self.saveTimer == nil) {
        self.saveTimer = [NSTimer scheduledTimerWithTimeInterval:10 target:self selector:@selector(deferredSave) userInfo:nil repeats:NO];
    }
}

- (NSString *)encodedClientIDAndSecret
{
    static NSString *sEncodedIDAndSecret = nil;
    
    if (sEncodedIDAndSecret == nil) {
        NSString *appDSUClientID = [OMHClient appDSUClientID];
        NSString *appDSUClientSecret = [OMHClient appDSUClientSecret];
        
        if (appDSUClientID != nil && appDSUClientSecret != nil) {
            NSString *string = [NSString stringWithFormat:@"%@:%@",
                                appDSUClientID,
                                appDSUClientSecret];
            
            NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
            sEncodedIDAndSecret = [data base64EncodedStringWithOptions:0];
        }
    }
    
    return sEncodedIDAndSecret;
}


#pragma mark - Property Accessors

+ (NSString *)defaultDSUBaseURL
{
    return kDefaultDSUBaseURL;
}

+ (NSString *)DSUBaseURL
{
    NSString * url = [[NSUserDefaults standardUserDefaults] stringForKey:kDSUBaseURLKey];
    if (url.length > 0) return url;
    else return kDefaultDSUBaseURL;
}

+ (void)setDSUBaseURL:(NSString *)DSUBaseURL
{
    if (DSUBaseURL.length > 0) {
        [[NSUserDefaults standardUserDefaults] setObject:DSUBaseURL forKey:kDSUBaseURLKey];
    }
    else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDefaultDSUBaseURL];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    [[self sharedClient] resetSessionManagers];
}

+ (NSString *)appGoogleClientID
{
    return [[NSUserDefaults standardUserDefaults] stringForKey:kAppGoogleClientIDKey];
}

+ (void)setAppGoogleClientID:(NSString *)appGoogleClientID
{
    [self gppSignIn].clientID = appGoogleClientID;
    [[NSUserDefaults standardUserDefaults] setObject:appGoogleClientID forKey:kAppGoogleClientIDKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSString *)serverGoogleClientID
{
    return [[NSUserDefaults standardUserDefaults] stringForKey:kServerGoogleClientIDKey];
}

+ (void)setServerGoogleClientID:(NSString *)serverGoogleClientID
{
    [self gppSignIn].homeServerClientID = serverGoogleClientID;
    [[NSUserDefaults standardUserDefaults] setObject:serverGoogleClientID forKey:kServerGoogleClientIDKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSString *)appDSUClientID
{
    return [[NSUserDefaults standardUserDefaults] stringForKey:kAppDSUClientIDKey];
}

+ (void)setAppDSUClientID:(NSString *)appDSUClientID
{
    [[NSUserDefaults standardUserDefaults] setObject:appDSUClientID forKey:kAppDSUClientIDKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSString *)appDSUClientSecret
{
    return [[NSUserDefaults standardUserDefaults] stringForKey:kAppDSUClientSecretKey];
}

+ (void)setAppDSUClientSecret:(NSString *)appDSUClientSecret
{
    [[NSUserDefaults standardUserDefaults] setObject:appDSUClientSecret forKey:kAppDSUClientSecretKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSString *)signedInUsername
{
    return [[NSUserDefaults standardUserDefaults] stringForKey:kSignedInUsernameKey];
}

+ (void)setSignedInUsername:(NSString *)signedInUsername
{
    [[NSUserDefaults standardUserDefaults] setObject:signedInUsername forKey:kSignedInUsernameKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}


- (NSMutableArray *)pendingDataPoints
{
    if (_pendingDataPoints == nil) {
        _pendingDataPoints = [NSMutableArray array];
    }
    return _pendingDataPoints;
}

- (NSMutableArray *)authRefreshCompletionBlocks
{
    if (_authRefreshCompletionBlocks == nil) {
        _authRefreshCompletionBlocks = [NSMutableArray array];
    }
    return _authRefreshCompletionBlocks;
}

- (BOOL)isSignedIn
{
    return (self.dsuAccessToken != nil && self.dsuRefreshToken != nil);
}

- (BOOL)isReachable
{
    if (!self.isSignedIn) return NO;
    return self.httpSessionManager.reachabilityManager.isReachable;
}

- (int)pendingDataPointCount
{
    return (int)self.pendingDataPoints.count;
}


#pragma mark - HTTP Session Manager

- (NSURL *)baseURL
{
    return [NSURL URLWithString:[OMHClient DSUBaseURL]];
}

- (AFHTTPSessionManager *)httpSessionManager
{
    if (_httpSessionManager == nil) {
        _httpSessionManager = [[AFHTTPSessionManager alloc] initWithBaseURL:self.baseURL];
        
        // setup reachability
        __weak OMHClient *weakSelf = self;
        [_httpSessionManager.reachabilityManager setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
            [weakSelf reachabilityStatusDidChange:status];
        }];
        
        // enable network activity indicator
        [[AFNetworkActivityIndicatorManager sharedManager] setEnabled:YES];
    }
    return _httpSessionManager;
}

- (AFHTTPSessionManager *)backgroundSessionManager
{
    if (_backgroundSessionManager == nil) {
        NSURLSessionConfiguration *config;
        if ([NSURLSessionConfiguration respondsToSelector:@selector(backgroundSessionConfigurationWithIdentifier:)]) {
            config = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:@"OMHBackgroundSessionConfiguration"];
        }
        else {
            config = [NSURLSessionConfiguration backgroundSessionConfiguration:@"OMHBackgroundSessionConfiguration"];
        }
        _backgroundSessionManager = [[AFHTTPSessionManager alloc] initWithBaseURL:self.baseURL sessionConfiguration:config];
        _backgroundSessionManager.requestSerializer = [AFJSONRequestSerializer serializer];
    }
    return _backgroundSessionManager;
}

- (void)setJSONResponseSerializerRemovesNulls:(BOOL)removeNulls
{
    ((AFJSONResponseSerializer *)self.httpSessionManager.responseSerializer).removesKeysWithNullValues = removeNulls;
}

- (void)resetSessionManagers
{
    _httpSessionManager = nil;
    _backgroundSessionManager = nil;
}

- (NSInteger)statusCodeFromSessionTask:(NSURLSessionTask *)task
{
    NSURLResponse *response = task.response;
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        return ((NSHTTPURLResponse *)response).statusCode;
    }
    else {
        return 0;
    }
}

- (void)getRequest:(NSString *)request
    withParameters:(NSDictionary *)parameters
   completionBlock:(void (^)(id responseObject, NSError *error, NSInteger statusCode))block
{
//    OMHLog(@"request: %@", request);
    [self.httpSessionManager GET:request parameters:parameters success:^(NSURLSessionDataTask *task, id responseObject) {
        // request succeeded
        block(responseObject, nil, [self statusCodeFromSessionTask:task]);
        
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        // request failed
        block(nil, error, [self statusCodeFromSessionTask:task]);
    }];
}

- (void)postRequest:(NSString *)request
     withParameters:(NSDictionary *)parameters
    completionBlock:(void (^)(id responseObject, NSError *error, NSInteger statusCode))block
{
    [self.httpSessionManager POST:request parameters:parameters success:^(NSURLSessionDataTask *task, id responseObject) {
        // request succeeded
        block(responseObject, nil, [self statusCodeFromSessionTask:task]);
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        // request failed
        block(nil, error, [self statusCodeFromSessionTask:task]);
    }];
}

- (void)authenticatedGetRequest:(NSString *)request
                 withParameters:(NSDictionary *)parameters
                completionBlock:(void (^)(id responseObject, NSError *error, NSInteger statusCode))block
{
//    OMHLog(@"request: %@", request);
    __block NSString *blockRequest = [request copy];
    __block NSDictionary *blockParameters = [parameters copy];
    __block void (^blockCompletionBlock)(id responseObject, NSError *error, NSInteger statusCode) = [block copy];
    [self refreshAuthenticationWithCompletionBlock:^(NSError *error) {
        if (error == nil) {
            [self getRequest:blockRequest withParameters:blockParameters completionBlock:blockCompletionBlock];
        }
        else {
            blockCompletionBlock(nil, error, 0);
        }
    }];
}

- (void)authenticatedPostRequest:(NSString *)request withParameters:(NSDictionary *)parameters
                completionBlock:(void (^)(id responseObject, NSError *error, NSInteger statusCode))block
{
    __block NSString *blockRequest = [request copy];
    __block NSDictionary *blockParameters = [parameters copy];
    __block void (^blockCompletionBlock)(id responseObject, NSError *error, NSInteger statusCode) = [block copy];
    [self refreshAuthenticationWithCompletionBlock:^(NSError *error) {
        if (error == nil) {
            [self postRequest:blockRequest withParameters:blockParameters completionBlock:blockCompletionBlock];
        }
        else {
            blockCompletionBlock(nil, error, 0);
        }
    }];
}

- (void)reachabilityStatusDidChange:(AFNetworkReachabilityStatus)status
{
    if (!self.isSignedIn) return;
    OMHLog(@"reachability status changed: %d", (int)status);
    // when network becomes reachable, re-authenticate user
    // and upload any pending survey responses
    BOOL reachable = (status > AFNetworkReachabilityStatusNotReachable);
    if (reachable) {
        if ([self accessTokenHasExpired] || !self.isAuthenticated) {
            [self refreshAuthenticationWithCompletionBlock:nil];
        }
        else {
            [self uploadPendingDataPoints];
        }
    }
    if (self.reachabilityDelegate != nil) {
        [self.reachabilityDelegate OMHClient:self reachabilityStatusChanged:reachable];
    }
}

- (BOOL)setDSUSignInHeader
{
    NSString *token = [self encodedClientIDAndSecret];
    OMHLog(@"setting dsu sign in header with token: %@", token);
    if (token) {
        self.httpSessionManager.requestSerializer = [AFHTTPRequestSerializer serializer];
        NSString *auth = [NSString stringWithFormat:@"Basic %@", token];
        [self.httpSessionManager.requestSerializer setValue:auth forHTTPHeaderField:@"Authorization"];
        return YES;
    }
    else {
        return NO;
    }
}

- (void)setDSUUploadHeader
{
    OMHLog(@"setting dsu upload header: %@", self.dsuAccessToken);
    if (self.dsuAccessToken) {
        self.httpSessionManager.requestSerializer = [AFJSONRequestSerializer serializer];
        NSString *auth = [NSString stringWithFormat:@"Bearer %@", self.dsuAccessToken];
        [self.httpSessionManager.requestSerializer setValue:auth forHTTPHeaderField:@"Authorization"];
        [self.backgroundSessionManager.requestSerializer setValue:auth forHTTPHeaderField:@"Authorization"];
    }
}

#pragma mark - Data Upload

- (void)submitDataPoint:(OMHDataPoint *)dataPoint
{
    [self submitDataPoint:dataPoint withMediaAttachments:nil];
}

- (void)submitDataPoint:(OMHDataPoint *)dataPoint withMediaAttachments:(NSArray *)mediaAttachments
{
    if (!self.isSignedIn) {
        OMHLog(@"attempting to submit data point while not signed in");
        return;
    }
    
    OMHRichMediaDataPoint *rmdp = nil;
    if (mediaAttachments == nil) {
        [self.pendingDataPoints addObject:dataPoint];\
    }
    else {
        rmdp = [OMHRichMediaDataPoint richMediaDataPointWithDataPoint:dataPoint mediaAttachments:mediaAttachments];
        [self.pendingRichMediaDataPoints addObject:rmdp];
    }
    

    [self saveClientState];
    
    if (self.isAuthenticating || !self.isReachable) return;
    
    if ([self accessTokenHasExpired] || !self.isAuthenticated) {
        [self refreshAuthenticationWithCompletionBlock:nil];
    }
    else {
        if (mediaAttachments == nil) {
            [self uploadDataPoint:dataPoint];
        }
        else {
            [self uploadRichMediaDataPoint:rmdp];
        }
    }
    
}

- (void)uploadPendingDataPoints
{
    OMHLog(@"uploading pending data points: %d, rich media: %d, isAuthenticating: %d", (int)self.pendingDataPoints.count, (int)self.pendingRichMediaDataPoints.count, self.isAuthenticating);
    
    for (OMHDataPoint *dataPoint in self.pendingDataPoints) {
        [self uploadDataPoint:dataPoint];
    }
    
    for (OMHRichMediaDataPoint *rmdp in self.pendingRichMediaDataPoints) {
        [self uploadRichMediaDataPoint:rmdp];
    }
}

- (void)uploadDataPoint:(OMHDataPoint *)dataPoint
{
    __block OMHDataPoint *blockDataPoint = dataPoint;
    [self postRequest:[self dataPointsRequestString] withParameters:dataPoint completionBlock:^(id responseObject, NSError *error, NSInteger statusCode) {
        if (error == nil || statusCode == 409) { // 409 means conflict, data point already uploaded
            OMHLog(@"upload data point succeeded: %@, status code: %d", blockDataPoint.header.headerID, (int)statusCode);
            [self.pendingDataPoints removeObject:blockDataPoint];
            [self saveClientState];
            if (self.uploadDelegate) {
                [self.uploadDelegate OMHClient:self didUploadDataPoint:blockDataPoint];
            }
        }
        else {
            OMHLog(@"upload data point failed: %@, status code: %d", blockDataPoint[@"header"][@"id"], (int)statusCode);
        }
    }];
}

- (void)uploadRichMediaDataPoint:(OMHRichMediaDataPoint *)rmdp
{
    NSError *requestError = nil;
    NSString *requestString = [[OMHClient DSUBaseURL] stringByAppendingPathComponent:[self dataPointsRequestString]];
    
    NSMutableURLRequest *request =
    [self.backgroundSessionManager.requestSerializer multipartFormRequestWithMethod:@"POST"
                                                 URLString:requestString
                                                parameters:nil
                                 constructingBodyWithBlock:^(id<AFMultipartFormData> formData)
     {
         [self buildResponseBodyForRichMediaDataPoint:rmdp formData:formData];
     }
                                                     error:&requestError];
    
    if (requestError != nil) {
        OMHLog(@"Failed to create upload request for rich media data point: %@", rmdp);
        return;
    }
    
    request.allowsCellularAccess = self.allowsCellularAccess;
    request = [self.backgroundSessionManager.requestSerializer requestWithMultipartFormRequest:request
                                                                   writingStreamContentsToFile:rmdp.tempFileURL
                                                                             completionHandler:^(NSError *error)
               {
                   if (error == nil) {
                       [self submitUploadRequest:request forRichMediaDataPoint:rmdp];
                   }
               }];
}

- (void)buildResponseBodyForRichMediaDataPoint:(OMHRichMediaDataPoint *)rmdp
                                      formData:(id<AFMultipartFormData>)formData
{
    NSDictionary *dataHeaders = @{@"Content-Disposition" :@"form-data; name=\"data\"",
                                  @"Content-Type" : @"application/json"};
    
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:rmdp.dataPoint
                                                       options:0
                                                         error:nil];
    
    [formData appendPartWithHeaders:dataHeaders body:jsonData];
    
    for (OMHMediaAttachment *mediaAttachment in rmdp.mediaAttachments) {
        NSError *error = nil;
        [formData appendPartWithFileURL:mediaAttachment.mediaAttachmentFileURL
                                   name:@"media"
                               fileName:mediaAttachment.mediaAttachmentFileName
                               mimeType:mediaAttachment.mediaAttachmentMimeType
                                  error:&error];
        if (error != nil) {
            OMHLog(@"Error appending form part for media attachment: %@, error: %@", mediaAttachment, error);
        }
    }
}

- (void)submitUploadRequest:(NSMutableURLRequest *)request forRichMediaDataPoint:(OMHRichMediaDataPoint *)rmdp
{
    NSURLSessionUploadTask *task =
    [self.backgroundSessionManager uploadTaskWithRequest:request
                                                fromFile:rmdp.tempFileURL
                                                progress:nil
                                       completionHandler:^(NSURLResponse *response, id responseObject, NSError *error)
     {
         NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
         OMHLog(@"Upload task completed with status code: %d", (int)statusCode);
         
         if (error == nil || statusCode == 409) {
             OMHLog(@"upload rich media data point succeeded: %@, status code: %d", rmdp.dataPoint.header.headerID, (int)statusCode);
             [rmdp removeTempFile];
             [self.pendingRichMediaDataPoints removeObject:rmdp];
             [self saveClientState];
             if (self.uploadDelegate) {
                 [self.uploadDelegate OMHClient:self didUploadDataPoint:rmdp.dataPoint];
             }
         }
         else {
             OMHLog(@"upload rich media data point failed: %@, status code: %d", rmdp.dataPoint.header.headerID, (int)statusCode);
         }

     }];
    
    [task resume];
    
    [self saveClientState];
}

- (NSString *)dataPointsRequestString
{
    return @"dataPoints";
}


#pragma mark - DSU Login

- (void)signInWithUsername:(NSString *)username password:(NSString *)password
{
    __block NSString *blockUsername = username;
    __block NSString *blockPassword = password;
    
    [self signInWithUsername:username password:password completionBlock:^(NSError *error) {
    
        if (error == nil) {
            [OMHClient setSignedInUsername:blockUsername];
            self.userPassword = blockPassword;
            [self unarchivePendingDataPointsForUsername:blockUsername];
        }
    }];
}

- (void)signInWithUsername:(NSString *)username password:(NSString *)password completionBlock:(void (^)(NSError *error))block
{
    if (![self setDSUSignInHeader]) return;
    
    NSString *request =  @"oauth/token";
    NSDictionary *parameters = @{@"grant_type" : @"password",
                                 @"username" : username,
                                 @"password" : password};
    
    self.isAuthenticating = YES;
    [self postRequest:request withParameters:parameters completionBlock:^(id responseObject, NSError *error, NSInteger statusCode) {
        
        if (block != nil) {
            block(error);
        }
        
        [self authenticationCompletedWithResponse:responseObject error:error];
    }];
}

- (void)refreshAuthenticationWithCompletionBlock:(void (^)(NSError *error))block
{
    OMHLog(@"refresh authentication, isAuthenticating: %d, refreshToken: %d", self.isAuthenticating, (self.dsuRefreshToken != nil));
    
    if (block) {
        [self.authRefreshCompletionBlocks addObject:[block copy]];
    }
    
    if (self.isAuthenticating || self.dsuRefreshToken == nil) return;
    
    self.isAuthenticating = YES;
    [self setDSUSignInHeader];
    
    NSString *request = @"oauth/token";
    NSDictionary *parameters = @{@"refresh_token" : self.dsuRefreshToken,
                                 @"grant_type" : @"refresh_token"};
    
    [self postRequest:request withParameters:parameters completionBlock:^(id responseObject, NSError *error, NSInteger statusCode) {
        if (error != nil) {
            OMHLog(@"auth refresh failed. attempting username/password sign-in");
            [self signInWithUsername:[OMHClient signedInUsername] password:self.userPassword completionBlock:nil];
        }
        else {
            [self authenticationCompletedWithResponse:responseObject error:error];
        }
    }];
}

- (void)authenticationCompletedWithResponse:(NSDictionary *)response error:(NSError *)error
{
    if (error == nil) {
        OMHLog(@"authentication success");
        
        [self storeAuthenticationResponse:response];
        [self setDSUUploadHeader];
        self.isAuthenticated = YES;
        [self uploadPendingDataPoints];
    }
    else {
        OMHLog(@"authentiation failed: %@", error);
        self.isAuthenticated = NO;
    }
    
    self.isAuthenticating = NO;
    
    for (void (^completionBlock)(NSError *) in self.authRefreshCompletionBlocks) {
        completionBlock(error);
    }
    [self.authRefreshCompletionBlocks removeAllObjects];
    
    if (self.signInDelegate != nil) {
        [self.signInDelegate OMHClient:self signInFinishedWithError:error];
    }
}

- (void)signOut
{
    OMHLog(@"sign out");
    [[OMHClient gppSignIn] signOut];
    self.userPassword = nil;
    self.dsuAccessToken = nil;
    self.dsuRefreshToken = nil;
    self.accessTokenDate = nil;
    self.accessTokenValidDuration = 0;
    [self saveClientState];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kSignedInUsernameKey];
}

- (void)storeAuthenticationResponse:(NSDictionary *)responseDictionary
{
    self.dsuAccessToken = responseDictionary[@"access_token"];
    self.dsuRefreshToken = responseDictionary[@"refresh_token"];
    self.accessTokenDate = [NSDate date];
    self.accessTokenValidDuration = [responseDictionary[@"expires_in"] doubleValue];
    [self saveClientState];
}

- (BOOL)accessTokenHasExpired
{
    NSDate *validDate = [self.accessTokenDate dateByAddingTimeInterval:self.accessTokenValidDuration];
    NSComparisonResult comp = [validDate compare:[NSDate date]];
    return (comp == NSOrderedAscending);
}

#pragma mark - Google Login

+ (UIButton *)googleSignInButton
{
    GPPSignInButton *googleButton = [[GPPSignInButton alloc] init];
    googleButton.style = kGPPSignInButtonStyleWide;
    return googleButton;
}

+ (GPPSignIn *)gppSignIn
{
    if (_gppSignIn == nil) {
        GPPSignIn *signIn = [GPPSignIn sharedInstance];
        signIn.shouldFetchGooglePlusUser = YES;
        signIn.shouldFetchGoogleUserEmail = YES;
        
        signIn.scopes = @[ @"profile" ];
        _gppSignIn = signIn;
    }
    return _gppSignIn;
}

- (void)finishedWithAuth: (GTMOAuth2Authentication *)auth
                   error: (NSError *) error
{
    OMHLog(@"Client received google error %@ and auth object %@",error, auth);
    if (error) {
        if (self.signInDelegate) {
            [self.signInDelegate OMHClient:self signInFinishedWithError:error];
        }
    }
    else {
        NSString *serverCode = [GPPSignIn sharedInstance].homeServerAuthorizationCode;
        
        if (serverCode != nil) {
            OMHLog(@"signed in user email: %@", auth.userEmail);
            [OMHClient setSignedInUsername:auth.userEmail];
            [self signInToDSUWithServerCode:serverCode];
        }
        else {
            OMHLog(@"failed to receive server code from google auth");
            [self signOut];
            if (self.signInDelegate) {
                NSError *serverCodeError = [NSError errorWithDomain:@"OMHClientServerCodeError" code:0 userInfo:nil];
                [self.signInDelegate OMHClient:self signInFinishedWithError:serverCodeError];
            }
            
        }
    }
}

- (void)signInToDSUWithServerCode:(NSString *)serverCode
{
    NSString *appDSUClientID = [OMHClient appDSUClientID];
    if (serverCode == nil || appDSUClientID == nil) return;
    if (![self setDSUSignInHeader]) return;
    
    NSString *request =  @"google-signin";
    NSString *code = [NSString stringWithFormat:@"fromApp_%@", serverCode];
    NSDictionary *parameters = @{@"code": code, @"client_id" : appDSUClientID};
    
    self.isAuthenticating = YES;
    [self getRequest:request withParameters:parameters completionBlock:^(id responseObject, NSError *error, NSInteger statusCode) {
        
        if (error == nil) {
            [self unarchivePendingDataPointsForUsername:[OMHClient signedInUsername]];
        }
        else {
            [self signOut];
        }
        
        [self authenticationCompletedWithResponse:responseObject error:error];
        
    }];
}

- (BOOL)handleURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    return [GPPURLHandler handleURL:url
                  sourceApplication:sourceApplication
                         annotation:annotation];
}



#pragma mark - Google Sign In Web View

- (void)handleOpenGoogleAuthNotification:(NSNotification *)notification
{
    NSURL *url = (NSURL *)notification.object;
    if (url == nil || self.signInDelegate == nil) return;
    
    UIWebView *webview = [[UIWebView alloc] init];
    webview.delegate = self;
    [webview loadRequest:[NSURLRequest requestWithURL:url]];
    
    UIActivityIndicatorView *activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    [webview addSubview:activityIndicator];
    [self centerViewInParent:activityIndicator];
    [activityIndicator startAnimating];
    self.activityIndicator = activityIndicator;
    
    UIViewController *vc = [[UIViewController alloc] init];
    vc.view = webview;
    vc.title = @"Sign In";
    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                  target:self
                                                                                  action:@selector(signInCancelButtonPressed)];
    vc.navigationItem.leftBarButtonItem = cancelButton;
    
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [self.signInDelegate presentViewController:nav animated:YES completion:nil];
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    NSURL *url = [request URL];
    NSString *bundleID = [[NSBundle mainBundle].bundleIdentifier lowercaseString];
    NSString *appPrefix = [bundleID stringByAppendingString:@":/oauth2callback"];
    if ([[url absoluteString] hasPrefix:appPrefix]) {
        [GPPURLHandler handleURL:url sourceApplication:@"com.google.chrome.ios" annotation:nil];
        
        // Looks like we did log in (onhand of the url), we are logged in, the Google APi handles the rest
        if (self.signInDelegate != nil) {
            [self.signInDelegate dismissViewControllerAnimated:YES completion:nil];
        }
        return NO;
    }
    return YES;
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    [self.activityIndicator removeFromSuperview];
    self.activityIndicator = nil;
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    if (self.signInDelegate != nil) {
        [self.signInDelegate dismissViewControllerAnimated:YES completion:^{
            [self.signInDelegate OMHClient:self signInFinishedWithError:error];
        }];
    }
}

- (void)signInCancelButtonPressed
{
    if (self.signInDelegate != nil) {
        [self.signInDelegate OMHClientSignInCancelled:self];
    }
}

#pragma mark - Layout Helpers

- (void)centerViewInParent:(UIView *)aView
{
    UIView *parent = aView.superview;
    if (parent == nil) return;
    
    aView.translatesAutoresizingMaskIntoConstraints = NO;
    
    [parent addConstraint:[NSLayoutConstraint
                           constraintWithItem:aView attribute:NSLayoutAttributeCenterX
                           relatedBy:NSLayoutRelationEqual
                           toItem:parent attribute:NSLayoutAttributeCenterX
                           multiplier:1.0f constant:0.0f]];
    
    [parent addConstraint:[NSLayoutConstraint
                           constraintWithItem:aView attribute:NSLayoutAttributeCenterY
                           relatedBy:NSLayoutRelationEqual
                           toItem:parent attribute:NSLayoutAttributeCenterY
                           multiplier:1.0f constant:0.0f]];
}

@end

