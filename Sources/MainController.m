/* Mines - MainController.m
 __  __
|  \/  | __  ____  ___  ____
|      |(__)|    |/ -_)(__ <
|__\/__||__||__|_|\___//___/
Copyright © 2013-2014 Manuel Sainz de Baranda y Goñi.
Released under the terms of the GNU General Public License v3. */

#import "MainController.h"
#import "Laser.h"
#import "Explosion.h"
#import "geometry.h"
#import "helpers.h"
#import "migrations.h"
#import "constants.h"
#import "NSWindow+CocoPlus.h"
#define kWindowMinimumWidth		259
#define LAST_UNFINISHED_GAME_PATH(base) STRING(@"%@/Last Unfinished Game.mines", base)

static GameValues typicalGames[4];

static const char *defaultsVariableNames[] = {
	"DefaultCellSize",
	"MaintainCellAspectRatio",
	"RememberGameSettings",
	"ResumeLastGameOnLaunch",
	"PlaySoundOnCellsDisclosed",
	"PlaySoundOnGameSolved",
	"PlaySoundOnMineFound",
	"PlaySoundOnHint",
	"ViewAnimationOnGameSolved",
	"ViewAnimationOnMineFound",
	"ViewAnimationOnHint",
	NULL
};


static NSAlert *AlertForPreferencesGameTooBig(NSUInteger width, NSUInteger height)
	{
	NSAlert *alert = [NSAlert
		alertWithMessageText:	   _("Alert.GameTooBigForDisplay.Title")
		defaultButton:		   _("Yes")
		alternateButton:	   _("No")
		otherButton:		   nil
		informativeTextWithFormat: _("Alert.GameTooBigForDisplay.PreferencesBody"), width, height];

	[alert setAlertStyle: NSInformationalAlertStyle];
	return alert;
	}


static NSAlert *AlertForGameTooBig(NSUInteger width, NSUInteger height)
	{
	NSAlert *alert = [NSAlert
		alertWithMessageText:	   _("Alert.GameTooBigForDisplay.Title")
		defaultButton:		   _("No")
		alternateButton:	   _("Yes")
		otherButton:		   nil
		informativeTextWithFormat: _("Alert.GameTooBigForDisplay.Body"), width, height];

	[alert setAlertStyle: NSInformationalAlertStyle];
	return alert;
	}


static void UpdateSound(NSString *fileName, BOOL enable, ALSound **sound)
	{
	if (enable) {if (!*sound) *sound = [[ALSound soundNamed: fileName] retain];}

	else	{
		[*sound release];
		*sound = nil;
		}
	}


@implementation MainController


#	pragma mark - Helpers


	- (void) setTimeLabelToSeconds: (NSUInteger) seconds
		{
		timeElapsedValueTextField.stringValue =
		STRING(@"%02lu:%02lu", (unsigned long)seconds / 60, (unsigned long)seconds % 60);
		}


	- (void) updateLabels
		{
		NSUInteger	   mineCount	= board.mineCount;
		NSUInteger	   clearedCount = board.clearedCount;
		NSNumberFormatter* formatter	= [[NSNumberFormatter alloc] init];

		[formatter setNumberStyle: NSNumberFormatterDecimalStyle];

		leftCounterValueTextField.stringValue =
		[formatter stringFromNumber: [NSNumber numberWithUnsignedInteger: clearedCount]];

		rightCounterValueTextField.stringValue =
		[formatter stringFromNumber: [NSNumber numberWithUnsignedInteger: board.width * board.height - mineCount - clearedCount]];

		[formatter release];
		totalMinesValueTextField.stringValue   = STRING(@"%lu", (unsigned long)mineCount);
		currentFlagsValueTextField.stringValue = STRING(@"%lu", (unsigned long)board.flagCount);
		}


	- (void) startTimerIfNeeded
		{
		[_gameOverTimer invalidate];

		if (_allowedTime)
			{
			[self setTimeLabelToSeconds: _timeLeft];
			[timeElapsedValueTextField setHidden: NO];

			if (_timeLeft && board.state == kBoardStateGame) _gameOverTimer = [NSTimer
				scheduledTimerWithTimeInterval: 1.0
				target:				self
				selector:			@selector(onOneSecondElapsed:)
				userInfo:			nil
				repeats:			YES];
			}

		else [timeElapsedValueTextField setHidden: YES];
		}


	- (void) stopTimer
		{
		[_gameOverTimer invalidate];
		_gameOverTimer = nil;
		}


	- (void) startNewGameWithValues: (GameValues *) values
		 time:			 (NSUInteger  ) time
		{
		[_snapshotPath release];

		_snapshotPath	    = nil;
		_allowedTime	    = _timeLeft = time;
		board.showMines	    = _flags.showMines;
		board.showGoodFlags = NO;

		[board newGameWithValues: *values];
		[self updateLabels];
		[self startTimerIfNeeded];
		}


	- (void) adjustWindowFrameInScreen: (NSScreen *) screen
		{
		NSWindow *window = self.window;
		NSRect windowFrame = window.frame;

		if (!screen) screen = self.window.screen;

		NSRect screenFrame = screen.visibleFrame;
		NSSize boardSize = board.bounds.size;
		NSSize borderSize = SizeSubtract(windowFrame.size, boardSize);

		NSSize targetBoardSize = NSMakeSize
			(_defaultCellSize * (CGFloat)board.width,
			 _defaultCellSize * (CGFloat)board.height);

		NSSize size = SizeAdd(borderSize, targetBoardSize);

		if (size.width < kWindowMinimumWidth)
			size = [self windowWillResize: window toSize: size];

		NSRect frame;

		if (SizeContains(screenFrame.size, size)) frame.size = size;

		else	{
			if (size.height / size.width > screenFrame.size.height / screenFrame.size.width)
				{
				// Ajustar al alto
				frame.size.height = screenFrame.size.height;

				frame.size.width =
				((frame.size.height - borderSize.height) * targetBoardSize.width) /
				targetBoardSize.height + borderSize.width;
				}

			else	{
				// Ajustar al ancho
				frame.size.width = screenFrame.size.width;

				frame.size.height =
				((frame.size.width - borderSize.width) * targetBoardSize.height) /
				targetBoardSize.width + borderSize.height;
				}
			}

		[window animateIntoScreenFrame: screenFrame fromTopCenterToSize: frame.size];
		}


	- (BOOL) areValidGameValues: (GameValues *) values
		 time:		     (NSUInteger  ) time
		{
		return ((values->width	   >= kGameMinimumWidth	    && values->width     <= kGameMaximumWidth ) &&
			(values->height	   >= kGameMinimumHeight    && values->height    <= kGameMaximumHeight) &&
			(time		   >= kGameMinimumTime	    && time		 <= kGameMaximumTime  ) &&
			(values->mineCount >= kGameMinimumMineCount && values->mineCount <= (values->width * values->height - 3)));
		}


	- (NSScreen *) suitableScreenForGameValues: (GameValues *) values
		{
		NSWindow *window = self.window;
		NSScreen *windowScreen = window.screen;

		NSSize size = SizeAdd
			(NSMakeSize(kCellMinimumSize * (CGFloat)values->width, kCellMinimumSize * (CGFloat)values->height),
			 SizeSubtract(window.frame.size, board.bounds.size));

		if (SizeContains(windowScreen.visibleFrame.size, size)) return windowScreen;

		for (NSScreen *screen in [NSScreen screens])
			if (SizeContains(screen.visibleFrame.size, size)) return screen;

		return nil;
		}


	- (void) readNewGameWindowCustomValues: (GameValues *) values
		 time:				(NSUInteger *) time
		{
		*time		  = timeLimitButton.state ? timeLimitTextField.stringValue.integerValue * 60 : 0;
		values->width	  = boardCustomWidthTextField.stringValue.integerValue;
		values->height	  = boardCustomHeightTextField.stringValue.integerValue;
		values->mineCount = boardCustomMineCountTextField.stringValue.integerValue;
		}


	- (void) setNewGameWindowToValues: (GameValues *) values
		 time:			   (NSUInteger	) time
		{
		NSUInteger i = 0;

		if (!time) for (; i < 4; i++) if (GameValuesAreEqual(values, &typicalGames[i]))
			{
			[gameTypeTabView selectTabViewItemAtIndex: 0];
			[typicalGameMatrix selectCellAtRow: i column: 0];
			goto disable_time_limit_controls;
			}

		if (time || i == 4)
			{
			[typicalGameMatrix selectCellAtRow: 1 column: 0];
			[gameTypeTabView selectTabViewItemAtIndex: 1];

			boardCustomWidthTextField.stringValue	  = STRING(@"%lu", (unsigned long)values->width);
			boardCustomHeightTextField.stringValue	  = STRING(@"%lu", (unsigned long)values->height);
			boardCustomMineCountTextField.stringValue = STRING(@"%lu", (unsigned long)values->mineCount);

			if (time)
				{
				timeLimitTextField.stringValue = STRING(@"%lu", (unsigned long)time / 60);
				timeLimitButton.state = NSOnState;
				[timeLimitTextField setEnabled: YES];
				}

			else	{
				disable_time_limit_controls:
				timeLimitTextField.stringValue = @"";
				timeLimitButton.state = NSOffState;
				[timeLimitTextField setEnabled: NO];
				}
			}

		[self changeDifficulty: typicalGameMatrix];
		}


	- (BOOL) saveSnapshotAtPath: (NSString *) path
		 error:		     (NSError **) error
		{
		NSError *writeError = NULL;
		BOOL result;
		NSMutableData *snapshot = [NSMutableData dataWithLength: [board snapshotSize] + sizeof(uint32_t[2])];
		void *buffer = (void *)[snapshot bytes];

		((uint32_t *)buffer)[0] = (uint32_t)_allowedTime;
		((uint32_t *)buffer)[1] = (uint32_t)_timeLeft;
		[board snapshot: buffer + sizeof(uint32_t[2])];
		result = [snapshot writeToFile: path options: NSDataWritingAtomic error: &writeError];
		if (error != NULL) *error = writeError;
		return result;
		}


	- (BOOL) loadSnapshotFromPath:	(NSString *) path
		 error:			(NSError **) error
		 abortOnGameSizeTooBig: (BOOL (^)(NSUInteger width, NSUInteger height)) abortOnGameSizeTooBig
		{
		NSError *readError = NULL;
		NSData *snapshot = [NSData dataWithContentsOfFile: path options: 0 error: &readError];

		if (readError != NULL)
			{
			if (error != NULL) *error = readError;
			return NO;
			}

		void *buffer = (void *)[snapshot bytes];
		size_t bufferSize = (size_t)[snapshot length];
		NSUInteger allowedTime;
		NSUInteger timeLeft;
		NSUInteger width = board.width, height = board.height;

		if (	bufferSize				<= sizeof(uint32_t[2])	||
			(allowedTime = ((uint32_t *)buffer)[0]) >  kGameMaximumTime	||
			(timeLeft    = ((uint32_t *)buffer)[1]) >  allowedTime		||

			!GameSnapshotTest
				(buffer	    + sizeof(uint32_t[2]),
				 bufferSize - sizeof(uint32_t[2]))
		)
			{
			if (error != NULL) *error = [NSError
				errorWithDomain: @"MinesError"
				code:		 0
				userInfo: [NSDictionary dictionaryWithObjectsAndKeys:
					_("Error.BadSnapshot.Title"), NSLocalizedDescriptionKey,
					_("Error.BadSnapshot.Body"),  NSLocalizedRecoverySuggestionErrorKey,
					nil]];

			return NO;
			}

		buffer	   += sizeof(uint32_t[2]);
		bufferSize -= 2;

		GameValues values;
		NSScreen *screen = nil;;

		GameSnapshotValues(buffer, bufferSize, &values);

		if (	(width != values.width || height != values.height)	&&
			!(screen = [self suitableScreenForGameValues: &values])	&&
			(abortOnGameSizeTooBig == NULL || abortOnGameSizeTooBig(values.width, values.height))
		)
			{
			if (error) *error = NULL;
			return NO;
			}

		[self stopTimer];
		_allowedTime = allowedTime;
		_timeLeft    = timeLeft;

		board.showMines = _flags.showMines;
		[board setSnapshot: buffer ofSize: bufferSize];

		BoardState boardState = board.state;

		if (boardState == kBoardStateResolved || boardState == kBoardStateGameOver)
			{
			board.showMines	    = YES;
			board.showGoodFlags = YES;
			}

		else board.showGoodFlags = NO;

		[self updateLabels];
		[self setNewGameWindowToValues: &values time: allowedTime];

		/*if	(boardState == kBoardStateResolved) [gameOverView youWin];
		else if (boardState == kBoardStateGameOver) [gameOverView youLose];
		else*/					    [gameOverView setHidden: YES];

		[_fireworks removeFromSuperview];
		_fireworks = nil;
		[_explosion cancelExplosion];
		[_taDahSound stop];
		[self startTimerIfNeeded];
		[self adjustWindowFrameInScreen: screen];
		if (error) *error = NULL;
		return YES;
		}


#	pragma mark - Callbacks


	- (void) onOneSecondElapsed: (NSTimer *) timer
		{
		[self setTimeLabelToSeconds: --_timeLeft];

		if (!_timeLeft)
			{
			[_gameOverTimer invalidate];
			_gameOverTimer = nil;
			board.showMines	  = YES;
			[gameOverView youLose];
			}
		}


	- (void) onWindowClosed: (NSNotification *) notification
		{
		NSWindow *window = notification.object;

		[[NSNotificationCenter defaultCenter]
			removeObserver: self
			name:		NSWindowWillCloseNotification
			object:		window];

		if (window.windowController == _preferencesController)
			{
			[_preferencesController release];
			_preferencesController = nil;
			}

		else	{
			[_aboutController release];
			_aboutController = nil;
			}
		}


	- (void) observeValueForKeyPath: (NSString     *) keyPath
		 ofObject:		 (id		) object
		 change:		 (NSDictionary *) change
		 context:		 (void	       *) context
		{
		id value = [[NSUserDefaultsController sharedUserDefaultsController] valueForKeyPath: keyPath];

		if	([keyPath isEqualToString: @"values.DefaultCellSize"	      ]) _defaultCellSize		  = round([(NSNumber *)value doubleValue]);
		else if ([keyPath isEqualToString: @"values.MaintainCellAspectRatio"  ]) _flags.maintainCellAspectRatio	  = [(NSNumber *)value boolValue];
		else if ([keyPath isEqualToString: @"values.RememberGameSettings"     ]) _flags.rememberGameSettings	  = [(NSNumber *)value boolValue];
		else if ([keyPath isEqualToString: @"values.ResumeLastGameOnLaunch"   ]) _flags.resumeLastGameOnLaunch	  = [(NSNumber *)value boolValue];
		else if ([keyPath isEqualToString: @"values.ViewAnimationOnGameSolved"]) _flags.viewAnimationOnGameSolved = [(NSNumber *)value boolValue];
		else if ([keyPath isEqualToString: @"values.ViewAnimationOnMineFound" ]) _flags.viewAnimationOnMineFound  = [(NSNumber *)value boolValue];
		else if ([keyPath isEqualToString: @"values.ViewAnimationOnHint"      ]) _flags.viewAnimationOnHint	  = [(NSNumber *)value boolValue];

		else if ([keyPath isEqualToString: @"values.PlaySoundOnCellsDisclosed"])
			UpdateSound(@"Disclose.wav", _flags.playSoundOnCellsDisclosed = [(NSNumber *)value boolValue], &_discloseSound);

		else if ([keyPath isEqualToString: @"values.PlaySoundOnGameSolved"])
			UpdateSound(@"Ta Dah.wav", _flags.playSoundOnGameSolved = [(NSNumber *)value boolValue], &_taDahSound);

		else if ([keyPath isEqualToString: @"values.PlaySoundOnMineFound"])
			UpdateSound(@"Explosion.wav", _flags.playSoundOnMineFound = [(NSNumber *)value boolValue], &_explosionSound);

		else if ([keyPath isEqualToString: @"values.PlaySoundOnHint"])
			UpdateSound(@"Laser.wav", _flags.playSoundOnHint = [(NSNumber *)value boolValue], &_laserBeamSound);
		}


#	pragma mark - Overwritten


	- (void) flagsChanged: (NSEvent *) event
		{
		NSUInteger flags = [event modifierFlags];

		if (flags & NSShiftKeyMask)
			{
			board.leftButtonAction = kBoardButtonActionFlag;
			currentFlagsSymbolButton.state = NSOnState;
			}

		else	{
			board.leftButtonAction = kBoardButtonActionNormal;
			currentFlagsSymbolButton.state = NSOffState;
			}
		}


#	pragma mark - NSApplicationDelegate Protocol


	- (void) applicationWillFinishLaunching: (NSNotification *) notification
		{
		//[[NSAlert alertWithError: ErrorForFile(_("Error.FileDoesNotExist"), @"paco")] runModal];

		//-------------------------------------.
		// Cargamos los XIBs con el interface. |
		//-------------------------------------'
		[NSBundle loadNibNamed: @"MainWindow" owner: self];
		[NSBundle loadNibNamed: @"NewGame"    owner: self];

		NSWindow *window = self.window;

		//-------------------------------------------------------------------.
		// Configuramos la funcionalidad de pantalla completa de la ventana. |
		//-------------------------------------------------------------------'
		//if ([window respondsToSelector: @selector(setCollectionBehavior:)])
		//	[window setCollectionBehavior: [window collectionBehavior] | NSWindowCollectionBehaviorFullScreenPrimary];

		//----------------------------------------------------------------------.
		// Establecemos los textos internacionalizados de la ventana principal. |
		//----------------------------------------------------------------------'
		window.title			       = _("Main.WindowTitle");
		leftCounterTitleTextField.stringValue  = _("Main.Toolbar.Clean");
		rightCounterTitleTextField.stringValue = _("Main.Toolbar.Remaining");

		//leftCounterTitleTextField.textColor = totalMinesValueTextField.textColor;
		//leftCounterValueTextField.textColor = totalMinesValueTextField.textColor;

		//-------------------------.
		// Creamos el cañón láser. |
		//-------------------------'
		(_cannon = [[Cannon alloc] initWithFrame: hintToolbarItem.view.bounds]).delegate = self;
		[hintToolbarItem setView: _cannon];
		[_cannon release];

		//--------------------------------------------------------.
		// Insertamos los contadores en la barra de herramientas. |
		//--------------------------------------------------------'
		[leftCounterToolbarItem	 setView: leftCounterView ];
		[leftCounterView release];
		[rightCounterToolbarItem setView: rightCounterView];
		[rightCounterView release];

		//------------------------------------------------------------------------------.
		// Añadimos efecto de incrustación a las etiquetas de la barra de herramientas. |
		//------------------------------------------------------------------------------'
		[leftCounterTitleTextField.cell	  setBackgroundStyle: NSBackgroundStyleRaised];
		[leftCounterValueTextField.cell	  setBackgroundStyle: NSBackgroundStyleRaised];
		[rightCounterTitleTextField.cell  setBackgroundStyle: NSBackgroundStyleRaised];
		[rightCounterValueTextField.cell  setBackgroundStyle: NSBackgroundStyleRaised];

		//---------------------------------------------------------------------------------.
		// Configuramos las imágenes de los botones de la barra de estado como plantillas. |
		// De esa forma, al ser activados, aparecerán resaltados en azul.		   |
		//---------------------------------------------------------------------------------'
		NSImage *image;

		image = [totalMinesSymbolButton.image copy];
		[image setTemplate: YES];
		totalMinesSymbolButton.image = image;
		[image release];

		image = [currentFlagsSymbolButton.image copy];
		[image setTemplate: YES];
		currentFlagsSymbolButton.image = image;
		[image release];

		if (IS_BELOW_YOSEMITE)
			{
			//------------------------------------------------------------------------.
			// Añadimos efecto de incrustación a las etiquetas de la barra de estado. |
			//------------------------------------------------------------------------'
			[totalMinesSymbolButton.cell	  setBackgroundStyle: NSBackgroundStyleRaised];
			[totalMinesValueTextField.cell	  setBackgroundStyle: NSBackgroundStyleRaised];
			[currentFlagsSymbolButton.cell	  setBackgroundStyle: NSBackgroundStyleRaised];
			[currentFlagsValueTextField.cell  setBackgroundStyle: NSBackgroundStyleRaised];
			[timeElapsedValueTextField.cell	  setBackgroundStyle: NSBackgroundStyleRaised];
			}

		//------------------------------------------------------.
		// Configuramos el callback para la vista de Game Over. |
		//------------------------------------------------------'
		gameOverView.target = self;
		gameOverView.action = @selector(new:);

		//-----------------------------------------------------------------------.
		// Añadimos el slider de transparencia al diálogo de selección de color. |
		//-----------------------------------------------------------------------'
		[[NSColorPanel sharedColorPanel] setShowsAlpha: YES];

		//--------------------------------------.
		// Cargamos la lista de juegos típicos. |
		//--------------------------------------'
		NSArray *games = [[NSDictionary dictionaryWithContentsOfFile:
			[[NSBundle mainBundle] pathForResource: @"Typical Games" ofType: @"plist"]]
				objectForKey: @"Games"];

		if (!games) FatalBundleCorruption();

		NSUInteger index = 4;
		NSDictionary *game;

		while (index)
			{
			game = [games objectAtIndex: --index];

			typicalGames[index].width     = [(NSNumber *)[game objectForKey: @"Width"    ] unsignedIntegerValue];
			typicalGames[index].height    = [(NSNumber *)[game objectForKey: @"Height"   ] unsignedIntegerValue];
			typicalGames[index].mineCount = [(NSNumber *)[game objectForKey: @"MineCount"] unsignedIntegerValue];
			}

		//-----------------------.
		// Creamos la explosión. |
		//-----------------------'
		_explosion = [[Explosion alloc] init];

		//-----------------------------------------------------------.
		// Establecemos los valores por defecto de las preferencias. |
		//-----------------------------------------------------------'
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

		[defaults registerDefaults: [NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithDouble: kCellDefaultSize],	     @"DefaultCellSize",
			[NSNumber numberWithBool: NO],			     @"MaintainCellAspectRatio",
			[NSNumber numberWithBool: YES],			     @"RememberGameSettings",
			[NSNumber numberWithBool: YES],			     @"ResumeLastGameOnLaunch",
			[NSNumber numberWithBool: YES],			     @"PlaySoundOnCellsDisclosed",
			[NSNumber numberWithBool: YES],			     @"PlaySoundOnGameSolved",
			[NSNumber numberWithBool: YES],			     @"PlaySoundOnMineFound",
			[NSNumber numberWithBool: YES],			     @"PlaySoundOnHint",
			[NSNumber numberWithBool: YES],			     @"ViewAnimationOnGameSolved",
			[NSNumber numberWithBool: YES],			     @"ViewAnimationOnMineFound",
			[NSNumber numberWithBool: YES],			     @"ViewAnimationOnHint",
			[NSNumber numberWithInteger: kGameDefaultWidth    ], @"Width",
			[NSNumber numberWithInteger: kGameDefaultHeight   ], @"Height",
			[NSNumber numberWithInteger: kGameDefaultMineCount], @"MineCount",
			[NSNumber numberWithInteger: kGameDefaultTime     ], @"Time",
			@"Cobalt",					     @"ThemeIdentifier",
			[NSNumber numberWithBool: YES],			     @"ThemeIsInternal",
			nil]];

		//-----------------------------------------------------------.
		// Leemos las preferencias y cargamos los sonidos activados. |
		//-----------------------------------------------------------'
		_defaultCellSize = [defaults doubleForKey: @"DefaultCellSize"];

		_flags.maintainCellAspectRatio	 = [defaults boolForKey: @"MaintainCellAspectRatio"  ];
		_flags.rememberGameSettings	 = [defaults boolForKey: @"RememberGameSettings"     ];
		_flags.resumeLastGameOnLaunch	 = [defaults boolForKey: @"ResumeLastGameOnLaunch"   ];
		_flags.viewAnimationOnGameSolved = [defaults boolForKey: @"ViewAnimationOnGameSolved"];
		_flags.viewAnimationOnMineFound	 = [defaults boolForKey: @"ViewAnimationOnMineFound" ];
		_flags.viewAnimationOnHint	 = [defaults boolForKey: @"ViewAnimationOnHint"      ];

		if ((_flags.playSoundOnCellsDisclosed = [defaults boolForKey: @"PlaySoundOnCellsDisclosed"]))
			_discloseSound = [[ALSound soundNamed: @"Disclose.wav"] retain];
		
		if ((_flags.playSoundOnGameSolved = [defaults boolForKey: @"PlaySoundOnGameSolved"]))
			_taDahSound = [[ALSound soundNamed: @"Ta Dah.wav"] retain];

		if ((_flags.playSoundOnMineFound = [defaults boolForKey: @"PlaySoundOnMineFound"]))
			_explosionSound	= [[ALSound soundNamed: @"Explosion.wav"] retain];

		if ((_flags.playSoundOnHint = [defaults boolForKey: @"PlaySoundOnHint"]))
			_laserBeamSound = [[ALSound soundNamed: @"Laser.wav"] retain];

		//---------------------------------------------------------------.
		// Cargamos y aplicamos el tema establecido en las preferencias. |
		// Si no es posible, utilizamos el tema por defecto.		 |
		//---------------------------------------------------------------'
		NSString*	themeIdentifier;
		NSArray*	dictionaries = nil;
		NSDictionary*	dictionary   = [defaults objectForKey: @"Theme"];
		Theme*		theme	     = nil;
		NSMutableArray*	themeImages  = nil;
		NSError*	error	     = nil;
		BOOL		errorFound;

		if (dictionary)
			{
			dictionary = [dictionary mutableCopy];
			[defaults removeObjectForKey: @"Theme"];

			if (!(theme = MigratedUserThemeFrom_v1(dictionary, &themeImages, &error)))
				{
				[theme	     release];
				[themeImages release];

				if (error)
					{
					[[NSAlert alertWithError: error] runModal];
					error = nil;
					}

				[[NSAlert alertWithError: Error
					(_("Error.PreviousVersionTheme.Title"),
					 _("Error.PreviousVersionTheme.Body"))]
						runModal];

				[dictionary release];
				dictionary = nil;
				goto try_set_v2_theme;
				}

			[dictionary release];
			[board setTheme: theme images: themeImages];
			[theme release];
			[themeImages release];
			[defaults setObject: theme.name forKey: @"ThemeIdentifier"];
			[defaults setBool: NO forKey: @"ThemeIsInternal"];
			}

		else	{
			try_set_v2_theme:

			errorFound = NO;
			themeIdentifier = [defaults stringForKey: @"ThemeIdentifier"];

			if ([defaults boolForKey: @"ThemeIsInternal"])
				{
				set_internal_theme:

				if (!dictionaries && !(dictionaries = [Theme internalDictionaries]))
					FatalBundleCorruption();

				for (NSDictionary *entry in dictionaries)
					if ([[entry objectForKey: @"Name"] isEqualToString: themeIdentifier])
						{
						dictionary = entry;
						break;
						}
				}

			else	{
				NSString *themesPath = BundleSupportSubdirectory(@"Themes", NO, &error);

				if (!themesPath)
					{
					if (error) [[NSAlert alertWithError: error] runModal];
					goto restore_default_theme;
					}

				dictionary = [NSDictionary dictionaryWithContentsOfFile:
					STRING(@"%@/%@.MinesTheme", themesPath, themeIdentifier)];
				}

			if (dictionary && [Theme validateDictionary: dictionary])
				{
				BOOL errors = YES;

				themeImages = [(theme = [[Theme alloc] initWithDictionary: dictionary])
					loadImages: &errors];

				if (!errors)
					{
					[board setTheme: theme images: themeImages];
					[theme release];
					return;
					}

				[theme release];
				Class errorClass = [NSError class];

				for (NSError *error in themeImages) if ([error isKindOfClass: errorClass])
					[[NSAlert alertWithError: error] runModal];
				}

			if (errorFound) FatalBundleCorruption();

			restore_default_theme:

			[[NSAlert alertWithError:
				Error(_("Error.InitialTheme.Title"), _("Error.InitialTheme.Body"))]
					runModal];

			errorFound = YES;
			dictionary = nil;
			[defaults removeObjectForKey: @"ThemeIdentifier"];
			[defaults removeObjectForKey: @"ThemeIsInternal"];
			goto try_set_v2_theme;
			}
		}


	- (void) applicationDidFinishLaunching: (NSNotification *) notification
		{
		NSString*      snapshotBasePath = BundleSupportDirectory(NO, NULL);
		NSFileManager* fileManager	= [NSFileManager defaultManager];
		NSString*      snapshotPath	= LAST_UNFINISHED_GAME_PATH(snapshotBasePath);
		BOOL	       snapshotExists	= snapshotBasePath && [fileManager fileExistsAtPath: snapshotPath];

		//--------------------------------------------------------------.
		// Si la aplicación se ha lanzado al abrir un juego guardado... |
		//--------------------------------------------------------------'
		if (board.state != kBoardStateNone)
			{
			//---------------------------------------------------------------------.
			// Eliminamos el archivo de la última partida no finalizada si existe. |
			//---------------------------------------------------------------------'
			if (snapshotExists) [fileManager removeItemAtPath: snapshotPath error: NULL];

			//------------------------------------------------------------------------.
			// Por un bug de Apple con OpenGL, la vista del tablero se posiciona	  |
			// sobre todas las demás al arrancar la aplicación. Si la partida salvada |
			// necesita mostrar la vista de GameOver, la mejor solución es ocultarla  |
			// y luego volver a mostrarla una vez que la ventana sea visible.	  |
			//------------------------------------------------------------------------'
			//[gameOverView setHidden: YES];
			}

		//----------------------.
		// En caso contrario... |
		//----------------------'
		else	{
			[gameOverView setHidden: YES];

			//-----------------------------------------------------------------------.
			// Si está activada la opción de continuar con el último juego inacabado |
			// al iniciar, intentamos cargarlo. Siempre eliminaremos el archivo.	 |
			//-----------------------------------------------------------------------'
			BOOL		 gameIsLoaded	  = NO;
			__block NSAlert* alert		  = nil;
			__block BOOL	 abortGameTooBig;

			if (snapshotExists)
				{
				if (	_flags.resumeLastGameOnLaunch &&

					[self	loadSnapshotFromPath:  snapshotPath
						error:		       NULL
						abortOnGameSizeTooBig: ^BOOL (NSUInteger width, NSUInteger height)
							{
							return abortGameTooBig =
								([(alert = AlertForPreferencesGameTooBig(width, height)) runModal]
								== NSAlertDefaultReturn);
							}]
				)
					gameIsLoaded = YES;

				[fileManager removeItemAtPath: snapshotPath error: NULL];
				}

			//-------------------------------------------------.
			// Si no se ha cargado el último juego inacabado   |
			// creamos uno nuevo a partir de las preferencias. |
			//-------------------------------------------------'
			if (!gameIsLoaded)
				{
				GameValues	values;
				NSUInteger	time;
				NSScreen*	screen	 = nil;
				NSUserDefaults*	defaults = [NSUserDefaults standardUserDefaults];

				values.width	 = [defaults integerForKey: @"Width"	];
				values.height	 = [defaults integerForKey: @"Height"	];
				values.mineCount = [defaults integerForKey: @"MineCount"];
				time		 = [defaults integerForKey: @"Time"	];

				if (	![self areValidGameValues: &values time: time] ||
					(!(screen = [self suitableScreenForGameValues: &values]) &&
					 (alert ? abortGameTooBig : ([AlertForPreferencesGameTooBig(values.width, values.height) runModal] == NSAlertDefaultReturn)))
				)
					{
					values.width	 = kGameDefaultWidth;
					values.height	 = kGameDefaultHeight;
					values.mineCount = kGameDefaultMineCount;
					time		 = kGameDefaultTime;
					}

				[self setNewGameWindowToValues: &values time: time];
				[self startNewGameWithValues:	&values time: time];
				[self adjustWindowFrameInScreen: screen];
				}
			}

		//----------------------------------------------.
		// Registramos listeners para las preferencias. |
		//----------------------------------------------'
		NSUserDefaultsController *defaultsController = [NSUserDefaultsController sharedUserDefaultsController];
		const char **variableName = defaultsVariableNames;

		while (*variableName != NULL) [defaultsController
			addObserver: self
			forKeyPath:  [NSString stringWithFormat: @"values.%s", *variableName++]
			options:     NSKeyValueObservingOptionPrior
			context:     NULL];

		//---------------------------------.
		// Mostramos la ventana principal. |
		//---------------------------------'
		NSWindow *window = self.window;

		[window makeKeyAndOrderFront: self];

		//-----------------------------------------------------------------------------.
		// Si el tablero contiene una partida terminada quiere decir que la aplicación |
		// se ha lanzado al abrir una partida salvada. A causa del fallo en OpenGL     |
		// necesitamos hacer visible de nuevo la vista de GameOver.		       |
		//-----------------------------------------------------------------------------'
		//if	(board.state == kBoardStateResolved) [gameOverView youWin];
		//else if (board.state == kBoardStateGameOver) [gameOverView youLose];

		//---------------------------------------------------------------------------.
		// Comprobamos si el ordenador tiene pantalla retina y mostramos, por ahora, |
		// un aviso advirtiendo de que las animaciones no se verán bien.	     |
		//---------------------------------------------------------------------------'
		/*NSScreen *screen = window.screen;

		if (	[screen respondsToSelector: @selector(backingScaleFactor)] &&
			[screen backingScaleFactor] != 1.0
		)
			{
			NSAlert *alert = [NSAlert
				alertWithMessageText:	   _("Alert.RetinaDisplayUntested.Title")
				defaultButton:		   nil
				alternateButton:	   nil
				otherButton:		   nil
				informativeTextWithFormat: _("Alert.RetinaDisplayUntested.Body")];

			[alert setAlertStyle: NSInformationalAlertStyle];
			[alert runModal];
			}*/
		}


	- (void) applicationWillTerminate: (NSNotification *) notification
		{
		//----------------------------------------.
		// Liberamos los objetos de la instancia. |
		//----------------------------------------'
		if (_aboutController	  ) [_aboutController.window	   performClose: self];
		if (_preferencesController) [_preferencesController.window performClose: self];

		//[self.window release];
		//[newGameWindow release];
		//newGameWindow = nil;
		[_explosion	 release];
		[_discloseSound	 release];
		[_explosionSound release];
		[_laserBeamSound release];
		[_taDahSound	 release];
		[_gameOverTimer	 invalidate];
		[_snapshotPath	 release];

		//---------------------------------------------------------------.
		// Guardamos en las preferencias los valores del juego actual	 |
		// o los eliminamos si el usuario no quiere que sean recordados. |
		//---------------------------------------------------------------'
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

		if (_flags.rememberGameSettings)
			{
			[defaults setInteger: board.width     forKey: @"Width"	  ];
			[defaults setInteger: board.height    forKey: @"Height"   ];
			[defaults setInteger: board.mineCount forKey: @"MineCount"];
			[defaults setInteger: _allowedTime    forKey: @"Time"	  ];
			}

		else	{
			[defaults removeObjectForKey: @"Width"	  ];
			[defaults removeObjectForKey: @"Height"	  ];
			[defaults removeObjectForKey: @"MineCount"];
			[defaults removeObjectForKey: @"Time"	  ];
			}

		[defaults synchronize];

		//-----------------------------------------------------------------------.
		// Si está activada la opción de continuar con el último juego inacabado |
		// al iniciar y el juego actual no se ha acabado, guardamos un snapshot. |
		//-----------------------------------------------------------------------'
		if (_flags.resumeLastGameOnLaunch && board.state == kBoardStateGame)
			{
			NSString *basePath = BundleSupportDirectory(YES, NULL);

			if (basePath)
				{
				NSFileManager *fileManager = [NSFileManager defaultManager];
				NSString *snapshotPath = LAST_UNFINISHED_GAME_PATH(basePath);

				//-----------------------------------------------------------------.
				// Si no podemos eliminar un snapshot ya presente, simplemente	   |
				// salimos, no molestamos al usuario. La próxima vez que se inicie |
				// el programa se cargará de nuevo el juego desde ese archivo.	   |
				//-----------------------------------------------------------------'
				if ([fileManager fileExistsAtPath: snapshotPath])
					if (![fileManager removeItemAtPath: snapshotPath error: NULL]) return;

				[self saveSnapshotAtPath: snapshotPath error: NULL];
				}
			}
		}


	- (void) applicationDidHide: (NSNotification *) notification
		{
		//------------------------------------------------------.
		// Por un bug de Apple con su implementación de OpenGL, |
		// la vista del tablero se posiciona en frente de todas |
		// las demás al minimizar la ventana principal u ocular	|
		// la aplicación. La única solución es sacarla junto a	|
		// todas las vistas que se solapan con ella y volverlas	|
		// a meter en el orden correcto.			|
		//------------------------------------------------------'
		NSView *contentView = self.window.contentView;

		[board retain];
		[board removeFromSuperview];
		[gameOverView retain];
		[gameOverView removeFromSuperview];

		if (_fireworks)
			{
			[_fireworks retain];
			[_fireworks removeFromSuperview];
			}

		[contentView addSubview: board];
		[board release];

		if (_fireworks)
			{
			[contentView addSubview: _fireworks];
			[_fireworks release];
			}

		[contentView addSubview: gameOverView];
		[gameOverView release];
		}


	- (BOOL) applicationShouldTerminateAfterLastWindowClosed: (NSApplication *) application
		{return YES;}


	- (BOOL) application: (NSApplication *) application
		 openFile:    (NSString	     *) fileName
		{
		if (!_busy)
			{
			NSError *error;

			if ([self
				loadSnapshotFromPath:  fileName
				error:		       &error
				abortOnGameSizeTooBig: ^BOOL (NSUInteger width, NSUInteger height)
					{return [AlertForGameTooBig(width, height) runModal] != NSAlertAlternateReturn;}]
			)
				{
				[_snapshotPath release];
				_snapshotPath = [fileName retain];
				return YES;
				}

			if (error) [[NSAlert alertWithError: error] runModal];
			}

		return NO;
		}


#	pragma mark - NSWindowDelegate Protocol


	- (void) windowWillClose: (NSNotification *) notification
		{
		[_aboutController	release];
		[_preferencesController release];
		_aboutController       = nil;
		_preferencesController = nil;
		}


	- (NSSize) windowWillResize: (NSWindow *) sender
		   toSize:	     (NSSize	) size
		{
		NSSize borderSize    = SizeSubtract(self.window.frame.size, board.bounds.size);
		NSSize fitSize	     = SizeSubtract(size, borderSize);
		NSSize boardUnitSize = NSMakeSize((CGFloat)board.width, (CGFloat)board.height);

		fitSize.width = fitSize.height * boardUnitSize.width / boardUnitSize.height;

		if (_flags.maintainCellAspectRatio)
			{
			if (fitSize.width + borderSize.width < kWindowMinimumWidth)
				fitSize.width = kWindowMinimumWidth - borderSize.width;

			CGFloat cellSize = floor(fitSize.width / boardUnitSize.width);

			fitSize.height = cellSize * boardUnitSize.height;
			fitSize.width  = cellSize * boardUnitSize.width;
			}

		else if (fitSize.width + borderSize.width < kWindowMinimumWidth)
			{
			fitSize.width = kWindowMinimumWidth - borderSize.width;
			fitSize.height = boardUnitSize.height * fitSize.width / boardUnitSize.width;
			}

		return SizeAdd(fitSize, borderSize);
		}


	- (void) windowDidMiniaturize: (NSNotification *) notification
		{[self applicationDidHide: notification];}


	- (void) windowDidBecomeMain:(NSNotification *)notification
		{[_cannon setHidden: NO];}


	- (void) windowDidResignMain:(NSNotification *)notification
		{[_cannon setHidden: YES];}


#	pragma mark - CannonDelegate Protocol


	- (void) cannonWantsToShoot: (Cannon *) cannon
		{
		if (!_busy && [board hintCoordinates: &_hintCoordinates])
			{
			if (_flags.viewAnimationOnHint)
				{
				_busy = YES;

				NSRect frame = [board frameForCoordinates: _hintCoordinates];
				frame.origin.x += frame.size.width  / 2.0;
				frame.origin.y += frame.size.height / 2.0;

				CGFloat size = board.bounds.size.width / board.width;
				CGFloat laserBeamWidth = size * 5.0 / _defaultCellSize; 

				cannon.blazeRadius = hypot(size, size) / 2.0;
				cannon.laserWidth  = laserBeamWidth > 5.0 ? 5.0 : laserBeamWidth;
				[cannon shootToPoint: [self.window convertPointToScreen: [board convertPoint: frame.origin toView: nil]]];
				}

			else	{
				[board discloseHintCoordinates: _hintCoordinates];
				if (board.state == kBoardStateResolved) [self boardDidWin: board];
				}
			}
		}


	- (void) cannonLaserWillStart: (Cannon *) cannon
		{
		if (_flags.playSoundOnHint)
			{
			[_laserBeamSound stop];
			[_laserBeamSound play];
			}
		}


	- (void) cannonLaserDidEnd: (Cannon *) cannon
		{
		[board discloseHintCoordinates: _hintCoordinates];
		if (board.state == kBoardStateResolved) [self boardDidWin: board];
		else [self updateLabels];
		}


	- (void) cannonDidEnd: (Cannon *) cannon
		{_busy = NO;}


#	pragma mark - BoardDelegate Protocol


	- (void) boardDidDiscloseCells: (Board *) sender
		{
		[self updateLabels];
		if (_flags.playSoundOnCellsDisclosed) [_discloseSound play];
		}


	- (void) boardDidChangeFlags: (Board *) sender
		{[self updateLabels];}


	- (void) boardDidWin: (Board *) sender
		{
		NSRect frame = board.frame;
		NSView *contentView = (NSView *)self.window.contentView;

		sender.showGoodFlags = YES;
		[self stopTimer];
		[self updateLabels];

		if (_flags.viewAnimationOnGameSolved)
			{
			_fireworks = [[Fireworks alloc] initWithFrame: frame];
			_fireworks.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
			[contentView addSubview: _fireworks];
			[_fireworks release];
			}

		[gameOverView youWin];

		if (_flags.playSoundOnGameSolved) [_taDahSound play];
		}


	- (void) explosionDidEnd: (Explosion *) explosion
		{
		_busy		    = NO;
		board.showMines	    = YES;
		board.showGoodFlags = YES;
		[gameOverView youLose];
		}


	- (void) board:			       (Board *) sender
		 didDiscloseMineAtCoordinates: (Q2DSize) coordinates;
		{
		[self stopTimer];
		[self updateLabels];

		NSRect frame = [sender convertRect: [board frameForCoordinates: coordinates] toView: nil];

		if (_flags.viewAnimationOnMineFound)
			{
			_busy = YES;

			[_explosion
				explodeAtPoint: [self.window convertPointToScreen: NSMakePoint
					(frame.origin.x + frame.size.width  / 2.0,
					 frame.origin.y + frame.size.height / 2.0)]
				target: self
				action: @selector(explosionDidEnd:)];
			}

		else	{
			board.showMines	    = YES;
			board.showGoodFlags = YES;
			[gameOverView youLose];
			}

		if (_flags.playSoundOnMineFound) [_explosionSound play];
		}


#	pragma mark - NSControlDelegate


	- (void) controlTextDidChange: (NSNotification *) notification
		{
		GameValues values;
		NSUInteger time;

		[self readNewGameWindowCustomValues: &values time: &time];
		[playButton setEnabled: [self areValidGameValues: &values time: time]];
		}


#	pragma mark - IB Actions


	- (IBAction) about: (id) sender
		{
		NSWindow *window;

		if (!_aboutController) [[NSNotificationCenter defaultCenter]
			addObserver: self
			selector:    @selector(onWindowClosed:)
			name:	     NSWindowWillCloseNotification
			object:	     window = (_aboutController = [[AboutController alloc] init]).window];

		else window = _aboutController.window;

		[window makeKeyAndOrderFront: self];
		}


	- (IBAction) preferences: (id) sender
		{
		NSWindow *window;

		if (!_preferencesController) [[NSNotificationCenter defaultCenter]
			addObserver: self
			selector:    @selector(onWindowClosed:)
			name:	     NSWindowWillCloseNotification
			object:	     window = (_preferencesController = [[PreferencesController alloc] initWithBoard: board]).window];

		else window = _preferencesController.window;

		[window makeKeyAndOrderFront: self];
		}


	- (IBAction) new: (id) sender
		{
		_busy = YES;
		[self stopTimer];

		boardCustomWidthTextField.stringValue     = STRING(@"%lu", (unsigned long)board.width	 );
		boardCustomHeightTextField.stringValue    = STRING(@"%lu", (unsigned long)board.height	 );
		boardCustomMineCountTextField.stringValue = STRING(@"%lu", (unsigned long)board.mineCount);

		[NSApp	beginSheet:	newGameWindow
			modalForWindow: self.window
			modalDelegate:	self
			didEndSelector:	nil
			contextInfo:	nil];

		[_fireworks removeFromSuperview];
		_fireworks = nil;
		}


	- (IBAction) restart: (id) sender
		{
		if (!_busy)
			{
			[board restart];
			board.showMines = _flags.showMines;
			board.showGoodFlags = NO;
			[self updateLabels];
			[gameOverView setHidden: YES];
			[_fireworks removeFromSuperview];
			_fireworks = nil;
			_timeLeft = _allowedTime;
			[_taDahSound stop];
			[self startTimerIfNeeded];
			}
		}


	- (IBAction) open: (id) sender
		{
		NSOpenPanel *panel = [NSOpenPanel openPanel];

		panel.allowedFileTypes = [NSArray arrayWithObject: @"mines"];

		if ([panel runModal] == NSFileHandlingPanelOKButton)
			{
			NSString *path = panel.URL.path;
			NSError *error;

			if ([self
				loadSnapshotFromPath:  path
				error:		       &error
				abortOnGameSizeTooBig: ^BOOL (NSUInteger width, NSUInteger height)
					{return [AlertForGameTooBig(width, height) runModal] != NSAlertAlternateReturn;}]
			)
				{
				[_snapshotPath release];
				_snapshotPath = [path retain];
				}

			else if (error) [[NSAlert alertWithError: error] runModal];
			}
		}


	- (IBAction) save: (id) sender
		{
		if (_snapshotPath)
			{
			NSError *error;

			if (![self saveSnapshotAtPath: _snapshotPath error: &error])
				[[NSAlert alertWithError: error] runModal];
			}

		else [self saveAs: sender];
		}


	- (IBAction) saveAs: (id) sender
		{
		NSSavePanel *panel = [NSSavePanel savePanel];

		NSDateComponents *today = [[NSCalendar currentCalendar]
			components:
				NSEraCalendarUnit    | NSYearCalendarUnit   |
				NSMonthCalendarUnit  | NSDayCalendarUnit    |
				NSHourCalendarUnit   | NSMinuteCalendarUnit |
				NSSecondCalendarUnit
			fromDate: [NSDate date]];

		panel.allowedFileTypes = [NSArray arrayWithObject: @"mines"];
		panel.canSelectHiddenExtension = YES;

		panel.nameFieldStringValue = STRING
			(@"%@'s Mines saved game (%04li-%02li-%02li %02li.%02li.%02li)",
			 NSFullUserName(),
			 (long)[today year], (long)[today month],  (long)[today day],
			 (long)[today hour], (long)[today minute], (long)[today second]);

		[self stopTimer];

		[panel beginSheetModalForWindow: self.window completionHandler: ^(NSInteger result)
			{
			if (result == NSFileHandlingPanelOKButton)
				{
				NSString *path = panel.URL.path;
				NSError *error;

				if ([self saveSnapshotAtPath: path error: &error])
					{
					[_snapshotPath release];
					_snapshotPath = [path retain];
					}

				else [[NSAlert alertWithError: error] runModal];
				}

			[self startTimerIfNeeded];
			}];
		}


	- (IBAction) toggleShowMines: (id) sender
		{
		_flags.showMines = !_flags.showMines;

		if (_flags.showMines)
			{
			minesShownMenuItem.title = _("Main.Menu.HideMines");
			totalMinesSymbolButton.state = NSOnState;
			}

		else	{
			minesShownMenuItem.title = _("Main.Menu.ShowMines");
			totalMinesSymbolButton.state = NSOffState;
			}

		if (board.state != kBoardStateGameOver) board.showMines = _flags.showMines;
		}


	- (IBAction) toggleInputIsAlwaysFlag: (NSButton *) sender
		{
		board.leftButtonAction = (sender.state == NSOnState)
			? kBoardButtonActionFlag
			: kBoardButtonActionNormal;
		}


	- (IBAction) changeDifficulty: (NSMatrix *) sender
		{
		const GameValues *values = &typicalGames[[sender selectedRow]];
		NSString *string;

		string = STRING(@"%lu", (unsigned long)values->width);
		boardWidthATextField.stringValue = string;
		boardWidthBTextField.stringValue = string;
		string = STRING(@"%lu", (unsigned long)values->height);
		boardHeightATextField.stringValue = string;
		boardHeightBTextField.stringValue = string;
		boardMineCountTextField.stringValue = STRING(@"%lu", (unsigned long)values->mineCount);
		}


	- (IBAction) toggleTimeLimit: (NSButton *) sender
		{
		BOOL value = sender.state == NSOnState;

		[timeLimitTextField	setEnabled: value];
		[timeLimitUnitTextField setEnabled: value];
		}


	- (IBAction) playNewGame: (id) sender
		{
		GameValues customValues, *values;
		NSUInteger time;

		if ([gameTypeTabView selectedTabViewItem] != typicalGameTabViewItem)
			{
			[self readNewGameWindowCustomValues: &customValues time: &time];
			values = &customValues;
			}

		else	{
			values = (GameValues *)&typicalGames[[typicalGameMatrix selectedRow]];
			time = 0;
			}

		NSScreen *screen = nil;
		BOOL sizeChanged = (values->height != board.height || values->width != board.width);

		if (	!sizeChanged					      ||
			(screen = [self suitableScreenForGameValues: values]) ||
			[AlertForGameTooBig(values->width, values->height) runModal] == NSAlertAlternateReturn
		)
			{
			_busy = NO;
			[NSApp endSheet: newGameWindow returnCode: 0];
			[newGameWindow orderOut: self];

			if (!time)
				{
				timeLimitTextField.stringValue = @"";
				timeLimitButton.state = NSOffState;
				[timeLimitTextField setEnabled: NO];
				}

			[gameOverView setHidden: YES];
			[self startNewGameWithValues: values time: time];
			if (sizeChanged) [self adjustWindowFrameInScreen: screen];
			}
		}


	- (IBAction) cancelNewGame: (id) sender
		{
		_busy = NO;
		[NSApp endSheet: newGameWindow returnCode: 0];
		[newGameWindow orderOut: self];
		if (board.state == kBoardStateGame) [self startTimerIfNeeded];
		}


@end

// EOF
