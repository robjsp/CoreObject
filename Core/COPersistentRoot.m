/*
	Copyright (C) 2013 Eric Wasylishen, Quentin Mathe
 
	Date:  July 2013
	License:  MIT  (see COPYING)
 */

#import "COPersistentRoot.h"
#import "COPersistentRoot+Private.h"
#import "COBranch.h"
#import "COBranch+Private.h"
#import "COEditingContext.h"
#import "COItem.h"
#import "COObject.h"
#import "COObject+Private.h"
#import "COObjectGraphContext.h"
#import "COObjectGraphContext+Private.h"
#import "CORevision.h"
#import "COSQLiteStore.h"
#import "COPersistentRootInfo.h"
#import "COBranchInfo.h"
#import "COEditingContext+Undo.h"
#import "COEditingContext+Private.h"
#import "COStoreTransaction.h"

NSString * const COPersistentRootDidChangeNotification = @"COPersistentRootDidChangeNotification";

@implementation COPersistentRoot

@synthesize parentContext = _parentContext, UUID = _UUID;
@synthesize branchesPendingDeletion = _branchesPendingDeletion;
@synthesize branchesPendingUndeletion = _branchesPendingUndeletion;

#pragma mark Creating a New Persistent Root -

- (id)init
{
	[self doesNotRecognizeSelector: _cmd];
	return nil;
}

// TODO: Could be debug only (measure how slow this check is)
- (void) validateNewObjectGraphContext: (COObjectGraphContext *)newContext
                           createdFrom: (COObjectGraphContext *)oldContext
{
	NSSet *newItemUUIDs = [NSSet setWithArray: [newContext itemUUIDs]];
	NSSet *oldItemUUIDs = [NSSet setWithArray: [oldContext itemUUIDs]];

	if ([newItemUUIDs isEqual: oldItemUUIDs])
		return;

	NSMutableSet *mismatchedItemUUIDsInNewContext = [newItemUUIDs mutableCopy];
	[mismatchedItemUUIDsInNewContext minusSet: oldItemUUIDs];
	NSMutableSet *mismatchedItemUUIDsInOldContext = [oldItemUUIDs mutableCopy];
	[mismatchedItemUUIDsInOldContext minusSet: newItemUUIDs];

	// FIXME: Unless we run GC phase in the new context, mismatches in the old
	// context will remain invisible.
	NSAssert2([mismatchedItemUUIDsInOldContext isEmpty],
		@"Mismatched item UUIDs accross identical object graph contexts, due "
		 "to persistent objects, belonging to the old object graph context %@, "
		 "present in a transient relationship (or several ones): \n%@", oldContext, 
		[oldContext loadedObjectsForUUIDs: [mismatchedItemUUIDsInOldContext allObjects]]);

	NSAssert2([mismatchedItemUUIDsInNewContext isEmpty],
		@"Mismatched item UUIDs accross identical object graph contexts, due "
		 "to persistent objects, belonging to the new object graph context %@, "
		 "present in a transient relationship (or several ones):  \n%@", newContext, 
		[newContext loadedObjectsForUUIDs: [mismatchedItemUUIDsInNewContext allObjects]]);
}

- (id) initWithInfo: (COPersistentRootInfo *)info
cheapCopyRevisionUUID: (ETUUID *)cheapCopyRevisionID
cheapCopyPersistentRootUUID: (ETUUID *)cheapCopyPersistentRootID
   parentBranchUUID: (ETUUID *)aBranchUUID
 objectGraphContext: (COObjectGraphContext *)anObjectGraphContext
      parentContext: (COEditingContext *)aCtxt
{
	if (info != nil)
    {
		INVALIDARG_EXCEPTION_TEST(anObjectGrapContext, anObjectGraphContext == nil);
    }
	if (anObjectGraphContext != nil)
	{
		INVALIDARG_EXCEPTION_TEST(info, info == nil);
		INVALIDARG_EXCEPTION_TEST(anObjectGraphContext, [anObjectGraphContext branch] == nil);
	}
	NILARG_EXCEPTION_TEST(aCtxt);

	SUPERINIT;
    
    _parentContext = aCtxt;
    _savedState =  info;
    _branchForUUID = [[NSMutableDictionary alloc] init];
	_branchesPendingDeletion = [NSMutableSet new];
	_branchesPendingUndeletion = [NSMutableSet new];
	if (anObjectGraphContext != nil)
	{
		_currentBranchObjectGraph = anObjectGraphContext;
	}
	else
	{
		_currentBranchObjectGraph = [[COObjectGraphContext alloc] init];
	}
	[_currentBranchObjectGraph setPersistentRoot: self];
	
    if (_savedState != nil)
    {
        _UUID =  [_savedState UUID];
        
        for (COBranchInfo *branchInfo in [[_savedState branchForUUID] allValues])
        {
            [self updateBranchWithBranchInfo: branchInfo];
        }
        
        _currentBranchUUID =  [_savedState currentBranchUUID];
		_lastTransactionID = _savedState.transactionID;
		_metadata = _savedState.metadata;
		
		[_currentBranchObjectGraph setItemGraph: [[self currentBranch] objectGraphContext]];
    }
    else
    {
        _UUID =  [ETUUID UUID];

		// TODO: Decide whether we should attempt to always allocate the object
		// graph context in the editing context methods rather than creating it
		// in COBranch initializer in some cases. Would make possible to write:
		//ETUUID *branchUUID = [anObjectGraphContext branchUUID];
        ETUUID *branchUUID =
			(anObjectGraphContext != nil ? [anObjectGraphContext branchUUID] : [ETUUID UUID]);
        COBranch *branch = [[COBranch alloc] initWithUUID: branchUUID
		                                objectGraphContext: nil
                                            persistentRoot: self
                                          parentBranchUUID: aBranchUUID
                                parentRevisionForNewBranch: cheapCopyRevisionID];
		[[branch objectGraphContext] setItemGraph: _currentBranchObjectGraph];

		[self validateNewObjectGraphContext: _currentBranchObjectGraph
		                        createdFrom: [branch objectGraphContext]];

        [_branchForUUID setObject: branch forKey: branchUUID];
        
        _currentBranchUUID =  branchUUID;
        _cheapCopyRevisionUUID =  cheapCopyRevisionID;
		_cheapCopyPersistentRootUUID =  cheapCopyPersistentRootID;
		
		if (_cheapCopyPersistentRootUUID != nil)
		{
			// FIXME: Make a proper metadata key for this
			self.metadata = @{ @"parentPersistentRoot" : [_cheapCopyPersistentRootUUID stringValue] };
		}
    }
	
	return self;
}

- (NSString *)description
{
	return [NSString stringWithFormat: @"<%@ %p - %@ - %@>",
		NSStringFromClass([self class]), self, _UUID, [[[self rootObject] entityDescription] name]];
}

- (NSString *)detailedDescription
{
	NSArray *properties = A(@"editingContext", @"currentBranch",
		@"branches", @"deleted", @"modificationDate", @"creationDate",
		@"parentPersistentRoot", @"isCopy", @"attributes", @"hasChanges",
		@"branchesPendingInsertion", @"branchesPendingUpdate",
		@"branchesPendingDeletion", @"branchesPendingUndeletion");
	NSMutableDictionary *options =
		[D(properties, kETDescriptionOptionValuesForKeyPaths,
		@"\t", kETDescriptionOptionPropertyIndent) mutableCopy];

	return [self descriptionWithOptions: options];
}

#pragma mark Persistent Root Properties -

- (NSDictionary *)metadata
{
	return [NSDictionary dictionaryWithDictionary: _metadata];
}

- (void)setMetadata: (NSDictionary *)aMetadata
{
    _metadata = [NSDictionary dictionaryWithDictionary: aMetadata];
    _metadataChanged = YES;
}

- (BOOL)isPersistentRoot
{
	return YES;
}

- (COEditingContext *)editingContext
{
	return [self parentContext];
}

- (BOOL)isDeleted
{
	if ([[_parentContext persistentRootsPendingUndeletion] containsObject: self])
		return NO;
	
	if ([[_parentContext persistentRootsPendingDeletion] containsObject: self])
		return YES;
	
    return [_savedState isDeleted];
}

- (void)setDeleted: (BOOL)deleted
{
    if (deleted)
    {
        [_parentContext deletePersistentRoot: self];
    }
    else
    {
        [_parentContext undeletePersistentRoot: self];
    }
}

- (NSDate *)modificationDate
{
	NSDate *maxDate = nil;

	for (COBranch *branch in [self branches])
	{
		NSDate *date = [[branch headRevision] date];

		if (maxDate != nil && [[date earlierDate: maxDate] isEqualToDate: date])
			continue;

		maxDate = date;
	}
	return maxDate;
}

- (NSDate *)creationDate
{
	return [[[self currentBranch] firstRevision] date];
}

- (COPersistentRoot *)parentPersistentRoot
{
	NSString *uuidString = self.metadata[@"parentPersistentRoot"];

	if (uuidString == nil)
		return nil;

	return [[self editingContext] persistentRootForUUID: [ETUUID UUIDWithString: uuidString]];
}

- (BOOL)isCopy
{
	return self.metadata[@"parentPersistentRoot"] != nil;
}

- (NSDictionary *)attributes
{
	return [[self store] attributesForPersistentRootWithUUID: _UUID];
}

#pragma mark Accessing Branches -

- (COBranch *)currentBranch
{
	return [_branchForUUID objectForKey: _currentBranchUUID];
}

- (void)setCurrentBranch: (COBranch *)aBranch
{
    _currentBranchUUID = [aBranch UUID];
	
	_currentBranchObjectGraph.branch = aBranch;
	[_currentBranchObjectGraph setItemGraph: [aBranch objectGraphContext]];
}

- (NSSet *)branches
{
    return [NSSet setWithArray: [[_branchForUUID allValues] filteredCollectionWithBlock: ^(id obj)
	{
		return (BOOL)![obj isDeleted];
	}]];
}

- (NSSet *)deletedBranches
{
    return [NSSet setWithArray: [[_branchForUUID allValues] filteredCollectionWithBlock: ^(id obj)
	{
		return (BOOL)[obj isDeleted];
	}]];
}

- (COBranch *)branchForUUID: (ETUUID *)aUUID
{
    return [_branchForUUID objectForKey: aUUID];
}

- (void)deleteBranch: (COBranch *)aBranch
{
    if ([aBranch isBranchUncommitted])
    {
        [_branchForUUID removeObjectForKey: [aBranch UUID]];
    }
	else if ([_branchesPendingUndeletion containsObject: aBranch])
	{
		[_branchesPendingUndeletion removeObject: aBranch];
	}
	else
	{
		[_branchesPendingDeletion addObject: aBranch];
	}
}

- (void)undeleteBranch: (COBranch *)aBranch
{
    if ([_branchesPendingDeletion containsObject: aBranch])
    {
        [_branchesPendingDeletion removeObject: aBranch];
    }
    else
    {
        [_branchesPendingUndeletion addObject: aBranch];
    }
}

#pragma mark Pending Changes -

- (NSSet *)branchesPendingInsertion
{
    return [[self branches] filteredCollectionWithBlock: ^(id obj)
	{
		return [obj isBranchUncommitted];
	}];
}

- (NSSet *)branchesPendingUpdate
{
    return [[self branches] filteredCollectionWithBlock: ^(id obj)
	{
		return [obj hasChanges];
	}];
}

- (BOOL)hasChanges
{
	if ([_branchesPendingDeletion count] > 0)
        return YES;
    
    if ([_branchesPendingUndeletion count] > 0)
        return YES;
	
	if (_metadataChanged)
        return YES;

	if ([_currentBranchObjectGraph hasChanges])
		return YES;
	
	for (COBranch *branch in [self branches])
	{
		if ([branch isBranchUncommitted])
            return YES;

		if ([branch hasChanges])
			return YES;
	}
	return NO;
}

- (void)discardAllChanges
{
	/* Discard changes in branches */

	for (COBranch *branch in [self branches])
	{
		if ([branch isBranchUncommitted])
			continue;
		
		[branch discardAllChanges];
	}

	/* Clear branches pending insertion */
	
	NSArray *branchesPendingInsertion = [[self branchesPendingInsertion] allObjects];
	
	[_branchForUUID removeObjectsForKeys: (id)[[branchesPendingInsertion mappedCollection] UUID]];
	ETAssert([[self branchesPendingInsertion] isEmpty]);

	/* Clear other pending changes */

	[_branchesPendingDeletion removeAllObjects];
	[_branchesPendingUndeletion removeAllObjects];

	if (_metadataChanged)
    {
		_metadata = [[[self persistentRootInfo] metadata] copy];
        _metadataChanged = NO;
    }
	
	ETAssert([self hasChanges] == NO);
}

#pragma mark Convenience -

- (COObjectGraphContext *)objectGraphContext
{
    return _currentBranchObjectGraph;
}

- (NSSet *)allObjectGraphContexts
{
	NSSet *objectGraphs = (id)[[[self branches] mappedCollection] objectGraphContext];
	return [objectGraphs setByAddingObject: _currentBranchObjectGraph];
}

- (id)rootObject
{
	return [[self objectGraphContext] rootObject];
}

- (void)setRootObject: (COObject *)aRootObject
{
	[[self objectGraphContext] setRootObject: aRootObject];
}

- (COObject *)loadedObjectForUUID: (ETUUID *)uuid
{
	return [[self objectGraphContext] loadedObjectForUUID: uuid];
}

- (CORevision *)currentRevision
{
    return [[self currentBranch] currentRevision];
}

- (void)setCurrentRevision: (CORevision *)revision
{
    [[self currentBranch] setCurrentRevision: revision];
}

- (CORevision *)headRevision
{
    return [[self currentBranch] headRevision];
}

- (void)setHeadRevision: (CORevision *)revision
{
    [[self currentBranch] setHeadRevision: revision];
}

- (COSQLiteStore *)store
{
	return [_parentContext store];
}

#pragma mark Committing Changes -

- (int64_t)lastTransactionID
{
	return _lastTransactionID;
}

- (void)setLastTransactionID: (int64_t) value
{
	_lastTransactionID = value;
}

- (BOOL)commitWithIdentifier: (NSString *)aCommitDescriptorId
					metadata: (NSDictionary *)additionalMetadata
				   undoTrack: (COUndoTrack *)undoTrack
                       error: (NSError **)anError
{
	NILARG_EXCEPTION_TEST(aCommitDescriptorId);
	INVALIDARG_EXCEPTION_TEST(additionalMetadata,
		[additionalMetadata containsKey: aCommitDescriptorId] == NO);

	NSMutableDictionary *metadata =
		[D(aCommitDescriptorId, kCOCommitMetadataIdentifier) mutableCopy];

	if (additionalMetadata != nil)
	{
		[metadata addEntriesFromDictionary: additionalMetadata];
	}
	return [_parentContext commitWithMetadata: metadata
		          restrictedToPersistentRoots: A(self)
								withUndoTrack: undoTrack
	                                    error: anError];
}

- (BOOL)commit
{
	return [self commitWithMetadata: [NSDictionary dictionary]];
}

- (BOOL)commitWithMetadata: (NSDictionary *)metadata
{
	return [_parentContext commitWithMetadata: metadata
                  restrictedToPersistentRoots: A(self)
								withUndoTrack: nil
	                                    error: NULL];
}

- (BOOL)isPersistentRootUncommitted
{
    return _savedState == nil;
}

- (void) saveCommitWithMetadata: (NSDictionary *)metadata transaction: (COStoreTransaction *)txn
{
	if ([self hasChanges]
		&& self.isDeleted
		&& [[self persistentRootInfo] isDeleted])
	{
		[NSException raise: NSGenericException
					format: @"Attempted to commit changes to deleted persistent root %@", self];
	}
	
	ETAssert([self currentBranch] != nil);
	ETAssert([self rootObject] != nil);
	ETAssert([[self rootObject] isRoot]);
	ETAssert([[self objectGraphContext] rootObject] != nil
			 || [[[self currentBranch] objectGraphContext] rootObject] != nil);
    
	if ([self isPersistentRootUncommitted])
	{		
        ETAssert([self currentBranch] != nil);
		BOOL usingCurrentBranchObjectGraph = YES;
		
        if (_cheapCopyRevisionUUID == nil)
        {
			ETAssert(!([[[self currentBranch] objectGraphContext] hasChanges]
					   && [_currentBranchObjectGraph hasChanges]));
			// FIXME: Move this into -createPersistentRootWithInitialItemGraph:
			// and make that take a id<COItemGraph>

			COObjectGraphContext *graphCtx = _currentBranchObjectGraph;
			if ([[[self currentBranch] objectGraphContext] hasChanges])
			{
				usingCurrentBranchObjectGraph = NO;
				graphCtx = [[self currentBranch] objectGraphContext];
			}
			
			// FIXME: check both _currentBranchObjectGraph and [branch objectGraphContext]
			// FIXME: After, update the other graph with the contents of the one we committed
			COItemGraph *graphCopy = [[COItemGraph alloc] initWithItemGraph: graphCtx];
						
            _savedState = [txn createPersistentRootWithInitialItemGraph: graphCopy
																   UUID: [self UUID]
                                                             branchUUID: [[self currentBranch] UUID]
													   revisionMetadata: metadata];
        }
        else
        {
			// Committing a cheap copy, so there must be a parent branch
			ETUUID *parentBranchUUID = [[[self currentBranch] parentBranch] UUID];
			ETAssert(parentBranchUUID != nil);
			ETAssert(_cheapCopyPersistentRootUUID != nil);
			
			const BOOL currentBranchObjectGraphHasChanges = [_currentBranchObjectGraph hasChanges];
			const BOOL specificBranchObjectGraphHasChanges = [[[self currentBranch] objectGraphContext] hasChanges];
			
			ETAssert(!(currentBranchObjectGraphHasChanges && specificBranchObjectGraphHasChanges));
			
			if (currentBranchObjectGraphHasChanges || specificBranchObjectGraphHasChanges)
			{
				ETUUID *newRevisionUUID = [ETUUID UUID];
				
				_savedState = [txn createPersistentRootCopyWithUUID: _UUID
										   parentPersistentRootUUID: _cheapCopyPersistentRootUUID
														 branchUUID: [[self currentBranch] UUID]
												   parentBranchUUID: parentBranchUUID
												initialRevisionUUID: newRevisionUUID];
				
				COItemGraph *modifiedItems;
				if (currentBranchObjectGraphHasChanges)
				{
					modifiedItems = [_currentBranchObjectGraph modifiedItemsSnapshot];
				}
				else
				{
					modifiedItems = [[[self currentBranch] objectGraphContext] modifiedItemsSnapshot];
					usingCurrentBranchObjectGraph = NO;
				}
				
				[txn writeRevisionWithModifiedItems: modifiedItems
									   revisionUUID: newRevisionUUID
										   metadata: metadata
								   parentRevisionID: _cheapCopyRevisionUUID
							  mergeParentRevisionID: nil
								 persistentRootUUID: _UUID
										 branchUUID: [[self currentBranch] UUID]];
			}
			else
			{
				_savedState = [txn createPersistentRootCopyWithUUID: _UUID
										   parentPersistentRootUUID: _cheapCopyPersistentRootUUID
														 branchUUID: [[self currentBranch] UUID]
												   parentBranchUUID: parentBranchUUID
												initialRevisionUUID: _cheapCopyRevisionUUID];
			}
        }
        ETAssert(_savedState != nil);
		ETUUID *initialRevID = [[_savedState currentBranchInfo] currentRevisionUUID];
		ETAssert(initialRevID != nil);

        [_parentContext recordPersistentRootCreation: self
		                         atInitialRevisionID: initialRevID];
        
        // N.B., we don't call -saveCommitWithMetadata: on the branch,
        // because the store call -createPersistentRootWithInitialContents:
        // handles creating the initial branch.
        
        [[self currentBranch] didMakeInitialCommitWithRevisionUUID: initialRevID transaction: txn];
		
		if (usingCurrentBranchObjectGraph)
		{
			[_currentBranchObjectGraph acceptAllChanges];
			[[[self currentBranch] objectGraphContext] setItemGraph: _currentBranchObjectGraph];
		}
		else
		{
			[[[self currentBranch] objectGraphContext] acceptAllChanges];
			[_currentBranchObjectGraph setItemGraph: [[self currentBranch] objectGraphContext]];
		}

		[self validateNewObjectGraphContext: _currentBranchObjectGraph
		                        createdFrom: [[self currentBranch] objectGraphContext]];
	}
    else
    {
        // Commit changes in our branches
        
        // N.B. Don't use -branches because that only returns non-deleted branches
        for (COBranch *branch in [_branchForUUID allValues])
        {
            [branch saveCommitWithMetadata: metadata transaction: txn];
        }
        
        // Commit a change to the current branch, if needed.
        // Needs to be done after because the above loop may create the branch
        if (![[_savedState currentBranchUUID] isEqual: _currentBranchUUID])
        {
			[txn setCurrentBranch: _currentBranchUUID
				forPersistentRoot: [self UUID]];
			
            [_parentContext recordPersistentRoot: self
                                setCurrentBranch: [self currentBranch]
                                       oldBranch: [self branchForUUID: [_savedState currentBranchUUID]]];
        }
        
        // N.B.: Ugly, the ordering of changes needs to be carefully controlled
        for (COBranch *branch in [_branchForUUID allValues])
        {
            [branch saveDeletionWithTransaction: txn];
        }
    }
	
	if (_metadataChanged)
	{
		[txn setMetadata: _metadata forPersistentRoot: _UUID];
		
		[_parentContext recordPersistentRootSetMetadata: self
		                                    oldMetadata: [_savedState metadata]];
		
		_metadataChanged = NO;
	}
	
	ETAssert([[self branchesPendingInsertion] isEmpty]);
	[_branchesPendingDeletion removeAllObjects];
	[_branchesPendingUndeletion removeAllObjects];
}

- (COPersistentRootInfo *)persistentRootInfo
{
    return _savedState;
}

- (void)reloadPersistentRootInfo
{
    COPersistentRootInfo *newInfo = [[self store] persistentRootInfoForUUID: [self UUID]];

    if (newInfo == nil)
		return;

	_savedState = newInfo;
}

- (void)didMakeNewCommit
{
	[self reloadPersistentRootInfo];
	
	for (COBranch *branch in [self branches])
	{
		[branch updateRevisions];
	}
}

#pragma mark Creating and Updating Branches -

- (COBranch *)makeBranchWithLabel: (NSString *)aLabel
                       atRevision: (CORevision *)aRev
                     parentBranch: (COBranch *)aParent
{
    COBranch *newBranch = [[COBranch alloc] initWithUUID: [ETUUID UUID]
	                                  objectGraphContext: nil
                                          persistentRoot: self
                                        parentBranchUUID: [aParent UUID]
                              parentRevisionForNewBranch: [aRev UUID]];
    
    [newBranch setMetadata: D(aLabel, @"COBranchLabel")];
    
    [_branchForUUID setObject: newBranch forKey: [newBranch UUID]];
    
    return newBranch;
}

- (COBranch *)makeBranchWithUUID: (ETUUID *)aUUID
                        metadata: (NSDictionary *)metadata
                      atRevision: (CORevision *)aRev
                    parentBranch: (COBranch *)aParent
{
    COBranch *newBranch = [[COBranch alloc] initWithUUID: aUUID
                                      objectGraphContext: nil
                                          persistentRoot: self
                                        parentBranchUUID: [aParent UUID]
                              parentRevisionForNewBranch: [aRev UUID]];
    
    if (metadata != nil)
    {
        [newBranch setMetadata: metadata];
    }

    [_branchForUUID setObject: newBranch forKey: [newBranch UUID]];
    
    return newBranch;
}

- (void)updateBranchWithBranchInfo: (COBranchInfo *)branchInfo
{
    COBranch *branch = [_branchForUUID objectForKey: [branchInfo UUID]];
    
    if (branch == nil)
    {
        branch = [[COBranch alloc] initWithUUID: [branchInfo UUID]
                             objectGraphContext: nil
                                 persistentRoot: self
                               parentBranchUUID: [branchInfo parentBranchUUID]
                     parentRevisionForNewBranch: nil];
        
        [_branchForUUID setObject: branch forKey: [branchInfo UUID]];
    }
    else
    {
        [branch updateWithBranchInfo: branchInfo];
    }
}

#pragma mark Notifications Handling -

- (void)storePersistentRootDidChange: (NSNotification *)notif
                       isDistributed: (BOOL)isDistributed
{
//	NSLog(@"++++Not ignoring update notif %d > %d (distributed: %d)",
//		  (int)notifTransaction, (int)_lastTransactionID, (int)isDistributed);
    
    COPersistentRootInfo *info =
		[[self store] persistentRootInfoForUUID: [self UUID]];
    _savedState = info;
    
    for (ETUUID *uuid in [info branchUUIDs])
    {
        COBranchInfo *branchInfo = [info branchInfoForUUID: uuid];
        [self updateBranchWithBranchInfo: branchInfo];
    }
    
	// FIXME: Factor out like -[COBranch updateBranchWithBranchInfo:]
	// TODO: Test that _everything_ is reloaded
	
    _currentBranchUUID =  [_savedState currentBranchUUID];
	[_currentBranchObjectGraph setItemGraph: [[self currentBranch] objectGraphContext]];
    _lastTransactionID = _savedState.transactionID;
    _metadata = _savedState.metadata;
	
	[self sendChangeNotification];
}

- (void)sendChangeNotification
{
    [[NSNotificationCenter defaultCenter]
		postNotificationName: COPersistentRootDidChangeNotification
		              object: self];
}

#pragma mark Previewing Old Revision -

- (COObjectGraphContext *)objectGraphContextForPreviewingRevision: (CORevision *)aRevision
{
    COObjectGraphContext *ctx = [[COObjectGraphContext alloc]
		initWithModelDescriptionRepository: [[self editingContext] modelDescriptionRepository]];
    id <COItemGraph> items = [[self store] itemGraphForRevisionUUID: [aRevision UUID]
	                                                 persistentRoot: _UUID];

    [ctx setItemGraph: items];

    return ctx;
}

@end
