#import "COPersistentRootInfo.h"

@implementation COPersistentRootInfo

@synthesize UUID = uuid_;
@synthesize currentBranchUUID = currentBranch_;
@synthesize branchForUUID = branchForUUID_;
@synthesize changeCount = _changeCount;
@synthesize deleted = _deleted;

- (void) dealloc
{
    [uuid_ release];
    [branchForUUID_ release];
    [currentBranch_ release];
    [super dealloc];
}

- (NSSet *) branchUUIDs
{
    return [NSSet setWithArray: [branchForUUID_ allKeys]];
}

- (COBranchInfo *)branchInfoForUUID: (ETUUID *)aUUID
{
    return [branchForUUID_ objectForKey: aUUID];
}
- (COBranchInfo *)currentBranchInfo
{
    return [self branchInfoForUUID: [self currentBranchUUID]];
}

@end