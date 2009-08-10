//
//  HRRequestOperation.m
//  HTTPRiot
//
//  Created by Justin Palmer on 1/30/09.
//  Copyright 2009 LabratRevenge LLC.. All rights reserved.
//

#import "HRRequestOperation.h"
#import "HRFormatJSON.h"
#import "HRFormatXML.h"
#import "NSObject+InvocationUtils.h"
#import "NSString+EscapingUtils.h"
#import "NSDictionary+ParamUtils.h"
#import "HRBase64.h"
#import "HROperationQueue.h"
#import "NSString+CapitalizedFirstWord.h"

@interface HRRequestOperation (PrivateMethods)
- (NSMutableURLRequest *)http;
- (NSArray *)formattedResults:(NSData *)data;
- (void)setDefaultHeadersForRequest:(NSMutableURLRequest *)request;
- (void)setAuthHeadersForRequest:(NSMutableURLRequest *)request;
- (NSMutableURLRequest *)configuredRequest;
- (id)formatterFromFormat;
- (NSURL *)composedURL;
+ (id)handleResponse:(NSHTTPURLResponse *)response error:(NSError **)error;
+ (NSString *)buildQueryStringFromParams:(NSDictionary *)params;
- (void)finish;
@end

@implementation HRRequestOperation
@synthesize timeout         = _timeout;
@synthesize requestMethod   = _requestMethod;
@synthesize path            = _path;
@synthesize options         = _options;
@synthesize formatter       = _formatter;
@synthesize delegate        = _delegate;
@synthesize name            = _name;

- (void)dealloc {
    [_path release];
    [_options release];
    [_formatter release];
    [_name release];
    [super dealloc];
}

- (id)initWithMethod:(HRRequestMethod)method path:(NSString*)urlPath options:(NSDictionary*)opts object:(id)obj selector:(SEL)selector {
                 
    if(self = [super init]) {
        _isExecuting    = NO;
        _isFinished     = NO;
        _isCancelled    = NO;
        _requestMethod  = method;
        _path           = [urlPath copy];
        _options        = [opts retain];
        _object         = obj;
        _timeout        = 30.0;
        _delegate       = [[opts valueForKey:@"delegate"] nonretainedObjectValue];
        _selector       = selector;
        _name           = [[opts valueForKey:@"name"] retain];
        _formatter      = [[self formatterFromFormat] retain];
    }

    return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Concurrent NSOperation Methods
- (void)start {
    [self willChangeValueForKey:@"isExecuting"];
    _isExecuting = YES;
    [self didChangeValueForKey:@"isExecuting"];
    
    NSURLRequest *request = [self configuredRequest];
    HRLog(@"FETCHING:%@ \nHEADERS:%@", [[request URL] absoluteString], [request allHTTPHeaderFields]);
    _connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
    
    if(_connection) {
        _responseData = [[NSMutableData alloc] init];        
    } else {
        [self finish];
    }    
}

- (void)finish {
    [_connection release];
    _connection = nil;
    
    [_responseData release];
    _responseData = nil;

    [self willChangeValueForKey:@"isExecuting"];
    [self willChangeValueForKey:@"isFinished"];

    _isExecuting = NO;
    _isFinished = YES;

    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
}

- (void)cancel {
    [self willChangeValueForKey:@"isCancelled"];
    
    [_connection cancel];    
    _isCancelled = YES;
    
    [self didChangeValueForKey:@"isCancelled"];
    
    [self finish];
}

- (BOOL)isExecuting {
   return _isExecuting;
}

- (BOOL)isFinished {
   return _isFinished;
}

- (BOOL)isCancelled {
   return _isCancelled;
}

- (BOOL)isConcurrent {
    return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSURLConnection delegates
- (SEL)selector:(NSString *)baseSelectorStr forDelegate:(id)delegate usedSelector:(BOOL *)usedSelector {
    if (delegate) {
        if (_name) {
            NSString *namedSelectorStr = [NSString stringWithFormat:@"%@%@", _name, [baseSelectorStr capitalizedFirstWord]];
            if (_selector) {
                NSString *namedSelectorWithSelectorStr = [NSString stringWithFormat:@"%@selector:", namedSelectorStr];
                SEL namedSelectorWithSelector = NSSelectorFromString(namedSelectorWithSelectorStr);
                if ([delegate respondsToSelector:namedSelectorWithSelector]) {
                    *usedSelector = YES;
                    return namedSelectorWithSelector;
                }
            }
            SEL namedSelector = NSSelectorFromString(namedSelectorStr);
            if ([delegate respondsToSelector:namedSelector]) {
                *usedSelector = NO;
                return namedSelector;
            }
        }
        if (_selector) {
            NSString *baseSelectorWithSelectorStr = [NSString stringWithFormat:@"%@selector:", baseSelectorStr];
            SEL baseSelectorWithSelector = NSSelectorFromString(baseSelectorWithSelectorStr);
            if ([delegate respondsToSelector:baseSelectorWithSelector]) {
                *usedSelector = YES;
                return baseSelectorWithSelector;
            }
        }
        SEL baseSelector = NSSelectorFromString(baseSelectorStr);
        if ([delegate respondsToSelector:baseSelector]) {
            *usedSelector = NO;
            return baseSelector;
        }
    }
    *usedSelector = NO;
    return NULL;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSHTTPURLResponse *)response {
    if (_delegate) {
        BOOL usedSelector;
        SEL didReceiveResponseSelector = [self selector:@"restConnection:didReceiveResponse:object:" forDelegate:_delegate usedSelector:&usedSelector];
        if (didReceiveResponseSelector) {
            NSInvocation *delegateInvocation = [NSInvocation invocationWithMethodSignature:[_delegate methodSignatureForSelector:didReceiveResponseSelector]];
            [delegateInvocation setTarget:_delegate];
            [delegateInvocation setSelector:didReceiveResponseSelector];
            [delegateInvocation setArgument:&connection atIndex:2];
            [delegateInvocation setArgument:&response atIndex:3];
            [delegateInvocation setArgument:&_object atIndex:4];
            if (usedSelector) {
                [delegateInvocation setArgument:&_selector atIndex:5];
            }
            [delegateInvocation retainArguments];
            [delegateInvocation performSelectorOnMainThread:@selector(invoke) withObject:nil waitUntilDone:NO];
            //[_delegate performSelectorOnMainThread:didReceiveResponseSelector withObjects:connection, response, _object, _selector, nil];
        }
    }
    
    NSError *error = nil;
    [[self class] handleResponse:(NSHTTPURLResponse *)response error:&error];
    
    if(error) {
        if (_delegate) {
            BOOL usedSelector;
            SEL didReceiveErrorSelector = [self selector:@"restConnection:didReceiveError:response:object:" forDelegate:_delegate usedSelector:&usedSelector];
            if (didReceiveErrorSelector) {
                NSInvocation *delegateInvocation = [NSInvocation invocationWithMethodSignature:[_delegate methodSignatureForSelector:didReceiveErrorSelector]];
                [delegateInvocation setTarget:_delegate];
                [delegateInvocation setSelector:didReceiveErrorSelector];
                [delegateInvocation setArgument:&connection atIndex:2];
                [delegateInvocation setArgument:&error atIndex:3];
                [delegateInvocation setArgument:&response atIndex:4];
                [delegateInvocation setArgument:&_object atIndex:5];
                if (usedSelector) {
                    [delegateInvocation setArgument:&_selector atIndex:6];
                }
                [delegateInvocation retainArguments];
                [delegateInvocation performSelectorOnMainThread:@selector(invoke) withObject:nil waitUntilDone:NO];
                //[_delegate performSelectorOnMainThread:didReceiveErrorSelector withObjects:connection, error, response, _object, _selector, nil];
            }
        }
        [connection cancel];
        [self finish];
    }
    
    [_responseData setLength:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {    
    [_responseData appendData:data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {    
    BOOL usedSelector;
    SEL didFailWithErrorSelector = [self selector:@"restConnection:didFailWithError:object:" forDelegate:_delegate usedSelector:&usedSelector];
    if (didFailWithErrorSelector) {
        NSInvocation *delegateInvocation = [NSInvocation invocationWithMethodSignature:[_delegate methodSignatureForSelector:didFailWithErrorSelector]];
        [delegateInvocation setTarget:_delegate];
        [delegateInvocation setSelector:didFailWithErrorSelector];
        [delegateInvocation setArgument:&connection atIndex:2];
        [delegateInvocation setArgument:&error atIndex:3];
        [delegateInvocation setArgument:&_object atIndex:4];
        if (usedSelector) {
            [delegateInvocation setArgument:&_selector atIndex:5];
        }
        [delegateInvocation retainArguments];
        [delegateInvocation performSelectorOnMainThread:@selector(invoke) withObject:nil waitUntilDone:NO];
        //[_delegate performSelectorOnMainThread:didFailWithErrorSelector withObjects:connection, error, _object, _selector, nil];
    }
    
    [self finish];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {    
    id results = [NSNull null];
    NSError *parseError = nil;
    
    if([_responseData length] > 0) {
        results = [[self formatter] decode:_responseData error:&parseError];
        
        if(parseError) {
            NSString *rawString = [[NSString alloc] initWithData:_responseData encoding:NSUTF8StringEncoding];

            BOOL usedSelector;
            SEL didReceiveParseErrorSelector = [self selector:@"restConnection:didReceiveParseError:responseBody:object:" forDelegate:_delegate usedSelector:&usedSelector];
            if (didReceiveParseErrorSelector) {
                NSInvocation *delegateInvocation = [NSInvocation invocationWithMethodSignature:[_delegate methodSignatureForSelector:didReceiveParseErrorSelector]];
                [delegateInvocation setTarget:_delegate];
                [delegateInvocation setSelector:didReceiveParseErrorSelector];
                [delegateInvocation setArgument:&connection atIndex:2];
                [delegateInvocation setArgument:&parseError atIndex:3];
                [delegateInvocation setArgument:&rawString atIndex:4];
                [delegateInvocation setArgument:&_object atIndex:5];
                if (usedSelector) {
                    [delegateInvocation setArgument:&_selector atIndex:6];
                }
                [delegateInvocation retainArguments];
                [delegateInvocation performSelectorOnMainThread:@selector(invoke) withObject:nil waitUntilDone:NO];
                //[_delegate performSelectorOnMainThread:didReceiveParseErrorSelector withObjects:connection, parseError, rawString, _object, _selector, nil];                
            }
            
            [rawString release];
            [self finish];
            
            return;
        }  
    }

    BOOL usedSelector;
    SEL didReturnResourceSelector = [self selector:@"restConnection:didReturnResource:object:" forDelegate:_delegate usedSelector:&usedSelector];
    if (didReturnResourceSelector) {
        NSInvocation *delegateInvocation = [NSInvocation invocationWithMethodSignature:[_delegate methodSignatureForSelector:didReturnResourceSelector]];
        [delegateInvocation setTarget:_delegate];
        [delegateInvocation setSelector:didReturnResourceSelector];
        [delegateInvocation setArgument:&connection atIndex:2];
        [delegateInvocation setArgument:&results atIndex:3];
        [delegateInvocation setArgument:&_object atIndex:4];
        if (usedSelector) {
            [delegateInvocation setArgument:&_selector atIndex:5];
        }
        [delegateInvocation retainArguments];
        [delegateInvocation performSelectorOnMainThread:@selector(invoke) withObject:nil waitUntilDone:NO];
        //[_delegate performSelectorOnMainThread:didReturnResourceSelector withObjects:connection, results, _object, _selector, nil];
    }
        
    [self finish];
}

////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Configuration

- (void)setDefaultHeadersForRequest:(NSMutableURLRequest *)request {
    NSDictionary *headers = [[self options] valueForKey:@"headers"];
    [request setValue:[[self formatter] mimeType] forHTTPHeaderField:@"Content-Type"];  
    [request addValue:[[self formatter] mimeType] forHTTPHeaderField:@"Accept"];
    if(headers) {
        for(NSString *header in headers) {
            NSString *value = [header valueForKey:header];
            if([header isEqualToString:@"Accept"]) {
                [request addValue:value forHTTPHeaderField:header];
            } else {
                [request setValue:value forHTTPHeaderField:header];
            }
        }        
    }
}

- (void)setAuthHeadersForRequest:(NSMutableURLRequest *)request {
    NSDictionary *authDict = [_options valueForKey:@"basicAuth"];
    NSString *username = [authDict valueForKey:@"username"];
    NSString *password = [authDict valueForKey:@"password"];
    
    if(username || password) {
        NSString *userPass = [NSString stringWithFormat:@"%@:%@", username, password];
        NSData   *upData = [userPass dataUsingEncoding:NSUTF8StringEncoding];
        NSString *encodedUserPass = [HRBase64 encode:upData];
        NSString *basicHeader = [NSString stringWithFormat:@"Basic %@", encodedUserPass];
        [request setValue:basicHeader forHTTPHeaderField:@"Authorization"];
    }
}

- (NSMutableURLRequest *)configuredRequest {
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    [request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
    [request setTimeoutInterval:_timeout];
    [self setDefaultHeadersForRequest:request];
    [self setAuthHeadersForRequest:request];
    
    NSURL *composedURL = [self composedURL];
    NSDictionary *params = [[self options] valueForKey:@"params"];
    id body = [[self options] valueForKey:@"body"];
    NSString *queryString = [[self class] buildQueryStringFromParams:params];
    
    if(_requestMethod == HRRequestMethodGet || _requestMethod == HRRequestMethodDelete) {
        NSString *urlString = [[composedURL absoluteString] stringByAppendingString:queryString];
        NSURL *url = [NSURL URLWithString:urlString];
        [request setURL:url];
        
        if(_requestMethod == HRRequestMethodGet) {
            [request setHTTPMethod:@"GET"];
        } else {
            [request setHTTPMethod:@"DELETE"];
        }
            
    } else if(_requestMethod == HRRequestMethodPost || _requestMethod == HRRequestMethodPut) {
        
        NSData *bodyData = nil;   
        if([body isKindOfClass:[NSDictionary class]]) {
            bodyData = [[body toQueryString] dataUsingEncoding:NSUTF8StringEncoding];
        } else if([body isKindOfClass:[NSString class]]) {
            bodyData = [body dataUsingEncoding:NSUTF8StringEncoding];
        } else if([body isKindOfClass:[NSData class]]) {
            bodyData = body;
        } else {
            [NSException exceptionWithName:@"InvalidBodyData"
                                    reason:@"The body must be an NSDictionary, NSString, or NSData"
                                  userInfo:nil];
        }
            
        [request setHTTPBody:bodyData];
        [request setURL:composedURL];
        
        if(_requestMethod == HRRequestMethodPost)
            [request setHTTPMethod:@"POST"];
        else
            [request setHTTPMethod:@"PUT"];
            
    }
    
    return request;
}

- (NSURL *)composedURL {
    NSURL *tmpURI = [NSURL URLWithString:_path];
    NSURL *baseURL = [_options objectForKey:@"baseURL"];

    if([tmpURI host] == nil && [baseURL host] == nil)
        [NSException raise:@"UnspecifiedHost" format:@"host wasn't provided in baseURL or path"];
    
    if([tmpURI host])
        return tmpURI;
        
    return [NSURL URLWithString:[[baseURL absoluteString] stringByAppendingPathComponent:_path]];
}

- (id)formatterFromFormat {
    NSNumber *format = [[self options] objectForKey:@"format"];
    id theFormatter = nil;
    switch([format intValue]) {
        case HRDataFormatJSON:
            theFormatter = [HRFormatJSON class];
        break;
        case HRDataFormatXML:
            theFormatter = [HRFormatXML class];
        break;
        default:
            theFormatter = [HRFormatJSON class];
        break;   
    }
    
    NSString *errorMessage = [NSString stringWithFormat:@"Invalid Formatter %@", NSStringFromClass(theFormatter)];
    NSAssert([theFormatter conformsToProtocol:@protocol(HRFormatterProtocol)], errorMessage); 
    
    return theFormatter;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Class Methods
+ (HRRequestOperation *)requestWithMethod:(HRRequestMethod)method path:(NSString*)urlPath options:(NSDictionary*)requestOptions object:(id)obj selector:(SEL)selector {
    id operation = [[self alloc] initWithMethod:method path:urlPath options:requestOptions object:obj selector:selector];
    [[HROperationQueue sharedOperationQueue] addOperation:operation];
    return [operation autorelease];
}

+ (id)handleResponse:(NSHTTPURLResponse *)response error:(NSError **)error {
    NSInteger code = [response statusCode];
    NSUInteger ucode = [[NSNumber numberWithInt:code] unsignedIntValue];
    NSRange okRange = NSMakeRange(200, 201);
    NSRange clientErrorRange = NSMakeRange(401, 99);
    NSRange serverErrorRange = NSMakeRange(500, 100);
    
    NSDictionary *headers = [response allHeaderFields];
    NSString *errorReason = [NSString stringWithFormat:@"%d Error: ", code];
    NSString *errorDescription;
    
    if(code == 300 || code == 302) {
        errorReason = [errorReason stringByAppendingString:@"RedirectNotHandled"];
        errorDescription = @"Redirection not handled";
    } else if(NSLocationInRange(ucode, okRange)) {
        return response;
    } else if(code == 400) {
        errorReason = [errorReason stringByAppendingString:@"BadRequest"];
        errorDescription = @"Bad request";
    } else if(code == 401) {
        errorReason = [errorReason stringByAppendingString:@"UnauthrizedAccess"];
        errorDescription = @"Unauthorized access to resource";
    } else if(code == 403) {
        errorReason = [errorReason stringByAppendingString:@"ForbiddenAccess"];
        errorDescription = @"Forbidden access to resource";
    } else if(code == 404) {
        errorReason = [errorReason stringByAppendingString:@"ResourceNotFound"];
        errorDescription = @"Unable to locate resource";
    } else if(code == 405) {
        errorReason = [errorReason stringByAppendingString:@"MethodNotAllowed"];
        errorDescription = @"Method not allowed";
    } else if(code == 409) {
        errorReason = [errorReason stringByAppendingString:@"ResourceConflict"];
        errorDescription = @"Resource conflict";
    } else if(code == 422) {
        errorReason = [errorReason stringByAppendingString:@"ResourceInvalid"];
        errorDescription = @"Invalid resource";
    } else if(NSLocationInRange(ucode, clientErrorRange)) {
        errorReason = [errorReason stringByAppendingString:@"ClientError"];
        errorDescription = @"Unknown Client Error";
    } else if(NSLocationInRange(ucode, serverErrorRange)) {
        errorReason = [errorReason stringByAppendingString:@"ServerError"];
        errorDescription = @"Unknown Server Error";
    } else {
        errorReason = [errorReason stringByAppendingString:@"ConnectionError"];
        errorDescription = @"Unknown status code";
    }
    
    if(error != nil) {
        NSDictionary *userInfo = [[[NSDictionary dictionaryWithObjectsAndKeys:
                                   errorReason, NSLocalizedFailureReasonErrorKey,
                                   errorDescription, NSLocalizedDescriptionKey, 
                                   headers, @"headers", 
                                   [[response URL] absoluteString], @"url", nil] retain] autorelease];
        *error = [NSError errorWithDomain:HTTPRiotErrorDomain code:code userInfo:userInfo];
    }

    return nil;
}

+ (NSString *)buildQueryStringFromParams:(NSDictionary *)theParams {
    if(theParams) {
        if([theParams count] > 0)
            return [NSString stringWithFormat:@"?%@", [theParams toQueryString]];
    }
    
    return @"";
}
@end
