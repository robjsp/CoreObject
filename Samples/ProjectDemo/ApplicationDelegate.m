#import "ApplicationDelegate.h"
#import "OutlineItem.h"
#import "TextItem.h"
#import "OutlineController.h"
#import "DrawingController.h"
#import "TextController.h"
#import "Document.h"
#import "HistoryInspectorController.h"
#import "SharingServer.h"
#import "SKTDrawDocument.h"

#define STORE_URL [NSURL URLWithString: [@"~/ProjectDemoStore" stringByExpandingTildeInPath]]

@implementation ApplicationDelegate

- (void)globalForward: (id)sender
{
	NSLog(@"Forward");
}

- (void)globalBack: (id)sender
{
	NSLog(@"Back");	
}

- (void)addStatusBarButtons
{
    NSStatusBar *bar = [NSStatusBar systemStatusBar];

    NSStatusItem *forwardButton = [bar statusItemWithLength:NSSquareStatusItemLength];
	[forwardButton setImage: [NSImage imageNamed: NSImageNameGoRightTemplate]];
    [forwardButton setHighlightMode:YES];
	[forwardButton setTarget: self];
	[forwardButton setAction: @selector(globalForward:)];
	[forwardButton retain];	
	
    NSStatusItem *backButton = [bar statusItemWithLength:NSSquareStatusItemLength];
	[backButton setImage: [NSImage imageNamed: NSImageNameGoLeftTemplate]];
    [backButton setHighlightMode:YES];
	[backButton setTarget: self];
	[backButton setAction: @selector(globalBack:)];
	[backButton retain];
}

- (void)showShelf: (id)sender
{
	[overlayShelf setIgnoresMouseEvents: NO];
	[overlayShelf setAlphaValue:0.0];
	[overlayShelf orderFront: sender];
	[[overlayShelf animator] setAlphaValue:1.0];
}

- (void)hideShelf: (id)sender
{
	[overlayShelf setIgnoresMouseEvents: YES];
	[[overlayShelf animator] setAlphaValue:0.0];
}


- (void)awakeFromNib
{
	context = [[COEditingContext alloc] initWithStoreCoordinator: 
			   [[[COStoreCoordinator alloc] initWithURL: STORE_URL] autorelease]];
	
	ETUUID *uuid = [[NSUserDefaults standardUserDefaults] UUIDForKey: @"projectDemoProjectUUID"];
	
	Project *loaded = [context objectForUUID: uuid];
	NSLog(@"Got UUID %@ from user defaults. The context returns: %@", uuid, loaded);
	
	if (nil != uuid && nil != loaded)
	{
		ASSIGN(project, (Project*)[context objectForUUID: uuid]);
		NSLog(@"Loading existing project %@ = %@", uuid, project);
		NSLog(@"It has %@ documents", [project documents]);
	}
	else
	{
		project = [[Project alloc] initWithContext: context];
		[context commit];
		NSLog(@"Creating a new project %@ = %@", [project uuid], project); 
		[[NSUserDefaults standardUserDefaults] setUUID: [project uuid]
												forKey: @"projectDemoProjectUUID"];
	}
	
	[project setDelegate: self];
	
	controllerForDocumentUUID = [[NSMutableDictionary alloc] init];
	
	[historyController setContext: context];
	
	// UI Setup
	[self addStatusBarButtons];
	desktopWindow = [[DesktopWindow alloc] init];
	projectNavWindow = [[ProjectNavWindow alloc] init];
	overlayShelf = [[OverlayShelf alloc] init];
	
	// Show existing documents
	[self projectDocumentsDidChange: project];
}

- (COEditingContext*)editingContext
{
	return context;
}

- (HistoryInspectorController*)historyController
{
	return historyController;
}

- (void)dealloc
{
	[project release];
	[controllerForDocumentUUID release];
	[desktopWindow release];
	[projectNavWindow release];
	[super dealloc];
}

- (void) newDocumentWithType: (NSString*)type rootObject: (COObject*)rootObj
{
	Document *document = [[[Document alloc] initWithContext: context] autorelease];
	[document setRootObject: rootObj];
	[document setDocumentName: [NSString stringWithFormat: @"Document %@", [[document uuid] stringValue]]];
	[document setDocumentType: type];
	
	[project addDocument: document];
	
	NSLog(@"Added a document model object %@, outline item %@", document, rootObj);
	NSLog(@"Changed objects %@", [context changedObjects]);
	[context commit];
	
	[newDocumentTypeWindow orderOut: nil];
}

- (IBAction) newTextDocument: (id)sender
{
	[self newDocumentWithType: @"text"
				   rootObject: [[[TextItem alloc] initWithContext: context] autorelease]];	
}
- (IBAction) newOutline: (id)sender
{
	[self newDocumentWithType: @"outline"
				   rootObject: [[[OutlineItem alloc] initWithContext: context] autorelease]];
}
- (IBAction) newDrawing: (id)sender
{
	[self newDocumentWithType: @"drawing"
				   rootObject: [[[SKTDrawDocument alloc] initWithContext: context] autorelease]];
}

/* Convenience */

- (NSWindowController*) keyDocumentController
{
	for (NSWindowController *controller in [controllerForDocumentUUID allValues])
	{
		if ([[controller window] isKeyWindow])
		{
			return controller;
		}
	}
	return nil;
}

- (Document *)keyDocument
{
	return [[self keyDocumentController] projectDocument];
}

/* NSResponder */

- (void)saveDocument: (id)sender
{
	[self checkpointWithName: nil];
}

- (void)saveDocumentAs: (id)sender
{
	NSString *name = [checkpointAsSheetController showSheet];
	if (name != nil)
	{
		[self checkpointWithName: name];
	}
}

- (void)checkpointWithName: (NSString*)name
{
	if ([name length] == 0)
	{
		name = @"Untitled Checkpoint";
	}
	[context commitWithType: kCOTypeCheckpoint
		   shortDescription: @"Checkpoint"
			longDescription: name];
}

- (void)undo:(id)sender
{
	
}
- (void)redo:(id)sender
{
	
}


- (IBAction)newProject: (id)sender
{
	Project *newProject = [[Project alloc] initWithContext: context];
	[context commit];
	NSLog(@"Creating a new project %@ = %@", [newProject uuid], newProject); 
	[newProject setDelegate: self];

	
}

- (IBAction)deleteProject: (id)sender
{
	
	
}



- (OutlineController*)controllerForDocumentRootObject: (COObject*)rootObject;
{
	for (Document *doc in [project documents])
	{
		if ([[[doc rootObject] uuid] isEqual: [rootObject uuid]])
		{
			return [controllerForDocumentUUID objectForKey: [doc uuid]];
		}
	}
	return nil;
}

/* Project delegate */

- (void)keyDocumentChanged: (NSNotification*)notif
{
	NSLog(@"Key document changed to: %@", [self keyDocumentController]);
	
	[tagWindowController setDocument: [self keyDocument]];
	
	// FIXME: update inspectors	
}

- (void)projectDocumentsDidChange: (Project*)p
{
	NSLog(@"projectDocumentsDidChange: called, loading %d documents", (int)[[p documents] count]);
	
	static NSDictionary *classForType;
	if (classForType == nil)
	{
		classForType = [[NSDictionary alloc] initWithObjectsAndKeys:
			[OutlineController class], @"outline",
			[DrawingController class], @"drawing",
			[TextController class], @"text",
			nil];
	}
	
	NSMutableSet *unwantedDocumentUUIDs = [NSMutableSet setWithArray:
										   [controllerForDocumentUUID allKeys]];
	
	for (Document *doc in [p documents])
	{
		[unwantedDocumentUUIDs removeObject: [doc uuid]];
		
		OutlineController *controller = [controllerForDocumentUUID objectForKey: [doc uuid]];
		if (controller == nil)
		{
			Class cls = [classForType objectForKey: [doc documentType]];
			assert(cls != Nil);
			
			// Create a new document controller
			controller = [[[cls alloc] initWithDocument: doc] autorelease];
			[controller showWindow: nil];
			[controllerForDocumentUUID setObject: controller forKey: [doc uuid]];
			// Observe key document changes
			[[NSNotificationCenter defaultCenter] addObserver: self
													 selector: @selector(keyDocumentChanged:)
														 name: NSWindowDidBecomeKeyNotification
													   object: [controller window]];
		}
	}
	
	for (ETUUID *unwanted in unwantedDocumentUUIDs)
	{
		NSWindow *window = [[controllerForDocumentUUID objectForKey: unwanted] window];
		[[NSNotificationCenter defaultCenter] removeObserver: self
														name: NSWindowDidBecomeKeyNotification
													  object: window];
		[window orderOut: nil];
		[controllerForDocumentUUID removeObjectForKey: unwanted];
	}
}

- (void) shareWithInspectorForDocument: (Document*)doc
{
	[sharingController shareWithInspectorForDocument: doc];
}

- (void)showSearchResults: (id)sender
{
	[searchWindow orderFront: self];
}

- (Project *)project
{
	return project;
}

@end