/* Mines - Board.m
 __  __
|  \/  | __  ____  ___	___
|      |(__)|    |/ -_)/_  \
|__\/__||__||__|_|\___/ /__/
Copyright © 2013-2015 Manuel Sainz de Baranda y Goñi.
Released under the terms of the GNU General Public License v3. */

#import "Board.h"
#import "geometry.h"
#import <Z/functions/base/Z2DValue.h>

//@interface NSFont (PrivateGlyph)
//	- (NSGlyph) _defaultGlyphForChar: (unichar) theChar;
//@end

#define kTextureIndexFlag	 8
#define kTextureIndexMine	 9
#define kTextureIndexExplosion	10
#define CELL_WARNING		MINESWEEPER_CELL_WARNING(cell)
#define CELL_IS(what)		MINESWEEPER_CELL_##what(cell)

static const unichar numbers_[8] = {L'1', L'2', L'3', L'4', L'5', L'6', L'7', L'8'};


/*static inline NSColor *DeviceColorFromGLColor(GLfloat *color)
	{
	return [NSColor
		colorWithDeviceRed: color[0]
		green:		    color[1]
		blue:		    color[2]
		alpha:		    1.0];
	}*/


#pragma mark - Snapshot


BOOL GameSnapshotTest(void *snapshot, size_t snapshotSize)
	{return (BOOL)!minesweeper_snapshot_test(snapshot, snapshotSize);}


BOOL GameSnapshotValues(void *snapshot, size_t snapshotSize, GameValues *values)
	{
	Z2DSize size;
	zsize mineCount;

	if (minesweeper_snapshot_values(snapshot, snapshotSize, &size, &mineCount, NULL))
		return NO;

	values->width	  = (NSUInteger)size.x;
	values->height	  = (NSUInteger)size.y;
	values->mineCount = (NSUInteger)mineCount;

	return YES;
	}


#pragma mark - Board Class


@implementation Board


	# pragma mark - Helpers


	- (void) setTextureGraphicContext
		{
		[NSGraphicsContext saveGraphicsState];

		_bitmap = [[NSBitmapImageRep alloc]
			initWithBitmapDataPlanes: NULL
			pixelsWide:		  (NSInteger)_textureSize
			pixelsHigh:		  (NSInteger)_textureSize
			bitsPerSample:		  8
			samplesPerPixel:	  4
			hasAlpha:		  YES
			isPlanar:		  NO
			colorSpaceName:		  NSDeviceRGBColorSpace
			bytesPerRow:		  4 * (NSInteger)_textureSize
			bitsPerPixel:		  32];

		NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep: _bitmap];

		[_bitmap release];
		[NSGraphicsContext setCurrentContext: context];
		}


	- (GLuint) createTextureFromBlock: (GLubyte *) data
		{
		GLuint name;

		glEnable(GL_TEXTURE_2D);
		//glEnable(GL_COLOR_MATERIAL);

		glGenTextures(1, &name);
		glBindTexture(GL_TEXTURE_2D, name);
		glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

		// Esto peta según el profiles de OpenGL
		//glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_BORDER,     0);

		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S,     GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T,     GL_CLAMP_TO_EDGE);

		glTexImage2D
			(GL_TEXTURE_2D, 0, GL_RGBA,
			 (GLsizei)_textureSize, (GLsizei)_textureSize,
			 0, GL_RGBA, GL_UNSIGNED_BYTE, data);

		glDisable(GL_TEXTURE_2D);
		//glDisable(GL_COLOR_MATERIAL);

		return name;
		}


	- (void) createTextureForImageAtIndex: (NSUInteger) index
		{
		NSColor *color;
		NSImage *image = [_themeImages objectAtIndex: index];
		NSRect frame = NSMakeRect(0.0, 0.0, _textureSize, _textureSize);

		[[NSColor clearColor] setFill];
		NSRectFill(frame);

		if ([image isKindOfClass: [NSImage class]])
			{
			frame = RectangleFitInCenter(frame, image.size);

			if ([(color = [_theme.imageColors objectAtIndex: index]) isEqualTo: [NSNull null]])
				{
				CGFloat components[4];

				[[color colorUsingColorSpace: [NSColorSpace deviceRGBColorSpace]] getComponents: components];
				//[color getComponents: components];

				[image	drawInRect: frame
					fromRect:   NSZeroRect
					operation:  NSCompositeSourceOver
					fraction:   components[3]];

				[[NSColor
					colorWithDeviceRed: components[0]
					green:		    components[1]
					blue:		    components[2]
					alpha:		    1.0]
				set];

				NSRectFillUsingOperation(frame, NSCompositeSourceAtop);
				}

			else [image
				drawInRect: frame
				fromRect:   NSZeroRect
				operation:  NSCompositeSourceOver
				fraction:   1.0];
			}

		_textureNames[8 + index] = [self createTextureFromBlock: [_bitmap bitmapData]];
		}


	- (void) createTextureForNumber: (NSUInteger) number
		{
		CGGlyph glyph;
		NSRect frame;
		NSBezierPath *path;
		NSAffineTransform *transform;
		NSString *fontName = _theme.fontName;

		NSFont *font = [NSFont
			fontWithName: fontName ? fontName : @"Lucida Grande Bold"
			size:	      floor(_textureSize * _theme.fontScaling)];

		CTFontGetGlyphsForCharacters((CTFontRef)font, &numbers_[number - 1], &glyph, 1);
		//NSLog(@"%@", [font _defaultGlyphForChar: numbers[number]] == glyph ? @"YES" : @"NO");

#		if DEBUG_GEOMETRY
			[[NSColor grayColor] setFill];
#		else
			[[NSColor clearColor] setFill];
//			[backgroundColor setFill];
#		endif

		NSRectFill(NSMakeRect(0.0, 0.0, _textureSize, _textureSize));

		path = [NSBezierPath bezierPath];
		[path moveToPoint: NSZeroPoint];
		[path appendBezierPathWithGlyph: glyph inFont: font];
		frame = path.controlPointBounds;

#		if DEBUG_GEOMETRY
			[[NSColor yellowColor] setFill];

			NSRectFill(NSMakeRect
				(_textureSize / 2.0 - frame.size.width  / 2.0,
				 _textureSize / 2.0 - frame.size.height / 2.0,
				 frame.size.width, frame.size.height));
#		endif

		transform = [NSAffineTransform transform];

		[transform
			translateXBy: round(-frame.origin.x + _textureSize / 2.0 - frame.size.width  / 2.0)
			yBy:	      round(-frame.origin.y + _textureSize / 2.0 - frame.size.height / 2.0)];

		[path transformUsingAffineTransform: transform];
		[[[_theme colorForNumber: number] colorUsingColorSpace: [NSColorSpace deviceRGBColorSpace]] setFill];
		[path fill];

		_textureNames[number - 1] = [self createTextureFromBlock: [_bitmap bitmapData]];
		}


	- (void) createNumberTextures
		{
		[self createTextureForNumber: 1];
		[self createTextureForNumber: 2];
		[self createTextureForNumber: 3];
		[self createTextureForNumber: 4];
		[self createTextureForNumber: 5];
		[self createTextureForNumber: 6];
		[self createTextureForNumber: 7];
		[self createTextureForNumber: 8];
		}


	- (void) createImageTextures
		{
		[self createTextureForImageWithKey: kThemeImageKeyFlag	   ];
		[self createTextureForImageWithKey: kThemeImageKeyMine	   ];
		[self createTextureForImageWithKey: kThemeImageKeyExplosion];
		}


	- (void) updateCellColorsForKey: (NSUInteger) key
		{
		CGFloat  delta		= _theme.cellBrightnessDelta;
		//NSColor* color	= [_theme colorForKey: key];
		NSColor* color		= [[_theme colorForKey: key] colorUsingColorSpace: [NSColorSpace deviceRGBColorSpace]];
		GLfloat* color1		= _cellColors1[key];
		CGFloat  components[4];

		[color getComponents: components];

		color1[0] = components[0];
		color1[1] = components[1];
		color1[2] = components[2];

		if (key <= kThemeColorKeyConfirmedFlag)
			{
			GLfloat* color2 = _cellColors2[key][0];

			if (_flags.flat)
				{
				color2[0] = color1[0] + delta;
				color2[1] = color1[1] + delta;
				color2[2] = color1[2] + delta;

				if (color2[0] > 1.0) color2[0] = 1.0; else if (color2[0] < 0.0) color2[0] = 0.0;
				if (color2[1] > 1.0) color2[1] = 1.0; else if (color2[1] < 0.0) color2[1] = 0.0;
				if (color2[2] > 1.0) color2[2] = 1.0; else if (color2[2] < 0.0) color2[2] = 0.0;
				}

			else	{
				NSColor *mask = [NSColor colorWithSRGBRed: 0.0 green: 0.0 blue: 0.0 alpha: 1.0];
				[[color blendedColorWithFraction: 0.625 ofColor: mask] getComponents: components];
				color2[0] = components[0];
				color2[1] = components[1];
				color2[2] = components[2];

				mask = [NSColor colorWithSRGBRed: 0.0 green: 0.0 blue: 0.0 alpha: 1.0];
				[[color blendedColorWithFraction: 0.25 ofColor: mask] getComponents: components];
				color2[3] = components[0];
				color2[4] = components[1];
				color2[5] = components[2];

				mask = [NSColor colorWithSRGBRed: 1.0 green: 1.0 blue: 1.0 alpha: 1.0];
				[[color blendedColorWithFraction: 0.75 ofColor: mask] getComponents: components];
				color2[6] = components[0];
				color2[7] = components[1];
				color2[8] = components[2];

				mask = [NSColor colorWithSRGBRed: 1.0 green: 1.0 blue: 1.0 alpha: 1.0];
				[[color blendedColorWithFraction: 0.5 ofColor: mask] getComponents: components];
				color2[ 9] = components[0];
				color2[10] = components[1];
				color2[11] = components[2];
				}
			}
		}


	- (Z2DSize) cellCoordinatesOfEvent: (NSEvent *) event
		{
		NSPoint point = [self convertPoint: [event locationInWindow] fromView: nil];
		NSSize size   = self.bounds.size;

		return z_2d_type(SIZE)
			((zsize)(point.x / (size.width  / (CGFloat)_values.width )),
			 (zsize)(point.y / (size.height / (CGFloat)_values.height)));
		}


	- (void) discloseCell
		{
		MinesweeperResult result = minesweeper_disclose(&_game, _coordinates);

		switch (result)
			{
			case 0:
			if (delegate) [delegate boardDidDiscloseCells: self];
			self.needsDisplay = YES;
			return;

			case MINESWEEPER_RESULT_SOLVED:
			_state = kBoardStateResolved;
			minesweeper_flag_all_mines(&_game);
			if (delegate) [delegate boardDidWin: self];
			self.needsDisplay = YES;
			return;

			case MINESWEEPER_RESULT_MINE_FOUND:
			//minesweeper_disclose_all_mines(_game);
			_state = kBoardStateGameOver;

			if (delegate) [delegate board: self didDiscloseMineAtCoordinates: _coordinates];
			self.needsDisplay = YES;
			return;
			}
		}


	- (void) toggleFlag
		{
		if (	_game.state == MINESWEEPER_STATE_PLAYING &&
			!MINESWEEPER_CELL_DISCLOSED(minesweeper_cell(&_game, _coordinates))
		)
			{
			minesweeper_toggle_flag(&_game, _coordinates, NULL);
			[delegate boardDidChangeFlags: self];
			self.needsDisplay = YES;
			}
		}


	- (void) revealRemaining
		{
		}


#	pragma mark - Accessors


	@synthesize state	     = _state;
	@synthesize values	     = _values;
	@synthesize leftButtonAction = _leftButtonAction;
	@synthesize theme	     = _theme;
	@synthesize themeImages      = _themeImages;


	- (NSUInteger)	width		{return _values.width;}
	- (NSUInteger)	height		{return _values.height;}
	- (NSUInteger)	mineCount	{return _values.mineCount;}
	- (NSUInteger)	flagCount	{return (NSUInteger)minesweeper_flag_count     (&_game);}
	- (NSUInteger)	clearedCount	{return (NSUInteger)minesweeper_disclosed_count(&_game);}
	- (BOOL)	showMines	{return _flags.showMines;}
	- (BOOL)	showGoodFlags	{return _flags.showGoodFlags;}


	- (void) setShowMines: (BOOL) value
		{
		_flags.showMines = value;
		self.needsDisplay = YES;
		}


	- (void) setShowGoodFlags: (BOOL) value
		{
		_flags.showGoodFlags = value;
		self.needsDisplay = YES;
		}


#	pragma mark - ThemeOwner Protocol


	- (void) updateNumbers
		{
		if (_game.state > MINESWEEPER_STATE_INITIALIZED)
			{
			if (_flags.texturesCreated) glDeleteTextures(8, _textureNames);
			[self setTextureGraphicContext];
			[self createNumberTextures];
			[NSGraphicsContext restoreGraphicsState];
			self.needsDisplay = YES;
			}
		}


	- (void) updateNumber: (NSUInteger) number
		{
		if (_game.state > MINESWEEPER_STATE_INITIALIZED)
			{
			if (_flags.texturesCreated) glDeleteTextures(1, &_textureNames[number - 1]);
			[self setTextureGraphicContext];
			[self createTextureForNumber: number];
			[NSGraphicsContext restoreGraphicsState];
			self.needsDisplay = YES;
			}

		}


	- (void) updateImageWithKey: (NSUInteger) key
		{
		if (_game.state > MINESWEEPER_STATE_INITIALIZED)
			{
			if (_flags.texturesCreated) glDeleteTextures(1, &_textureNames[8 + key]);
			[self setTextureGraphicContext];
			[self createTextureForImageWithKey: key];
			[NSGraphicsContext restoreGraphicsState];
			self.needsDisplay = YES;
			}
		}


	- (void) updateColorWithKey: (NSUInteger) key
		{
		[self updateCellColorsForKey: key];
		self.needsDisplay = YES;
		}


	- (void) updateAlternateColors
		{
		CGFloat delta = _theme.cellBrightnessDelta;

		_flags.flat = _theme.flat;

		//NSLog(@"updateAlternateColors");

		//if (_cellBrightnessDelta != delta)
		//	{
			_cellBrightnessDelta = delta;

			[self updateCellColorsForKey: kThemeColorKeyCovered      ];
			[self updateCellColorsForKey: kThemeColorKeyClean	 ];
			[self updateCellColorsForKey: kThemeColorKeyFlag	 ];
			[self updateCellColorsForKey: kThemeColorKeyConfirmedFlag];
			[self updateCellColorsForKey: kThemeColorKeyMine	 ];
			[self updateCellColorsForKey: kThemeColorKeyWarning      ];
		//	}

		if (_game.state > MINESWEEPER_STATE_INITIALIZED) self.needsDisplay = YES;
		}


#	pragma mark - Overwritten


	- (id) initWithCoder: (NSCoder *) coder
		{
		if ((self = [super initWithCoder: coder]))
			{
			minesweeper_initialize(&_game);

			if ([self respondsToSelector: @selector(setWantsBestResolutionOpenGLSurface:)])
				[self setWantsBestResolutionOpenGLSurface: YES];
			}

		return self;
		}


	- (void) dealloc
		{
		if (_flags.texturesCreated) glDeleteTextures(11, _textureNames);
		minesweeper_finalize(&_game);

		[_theme	      release];
		[_themeImages release];
		[super	      dealloc];
		}


#	define SET_COLOR(color) glColor3fv(&_cellColors1[kThemeColorKey##color * 3])

	static GLdouble const cellVertices[4 * 2] = {0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0};

	static GLdouble const cellEdgeVertices[4][4 * 2] = {
		{0.0,	0.0,   1.0,   0.0,   0.875, 0.125, 0.125, 0.125}, // Bottom
		{0.875, 0.125, 1.0,   0.0,   1.0,   1.0,   0.875, 0.875}, // Right
		{0.125, 0.875, 0.875, 0.875, 1.0,   1.0,   0.0,   1.0  }, // Top
		{0.0,	0.0,   0.125, 0.125, 0.125, 0.875, 0.0,	  1.0  }, // Left
	};

	- (void) drawRect: (NSRect) frame
		{
		if (_game.state == MINESWEEPER_STATE_INITIALIZED)
			{
			glClearColor(0.0, 0.0, 0.0, 1.0);
			glClear(GL_COLOR_BUFFER_BIT);
			}

		else	{
			MinesweeperCell cell;

			glEnable(GL_BLEND);
			glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
			glEnable(GL_TEXTURE_2D);
			glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);

#			if DEBUG_GEOMETRY
				glClearColor
					(palette[paletteIndex][kThemeColorKeyClean * 3],
					 palette[paletteIndex][kThemeColorKeyClean * 3 + 1],
					 palette[paletteIndex][kThemeColorKeyClean * 3 + 2],
					 1);

				glClear(GL_COLOR_BUFFER_BIT);
#			endif

			GLdouble cellX;
			GLdouble cellY;
			GLint	 x, y;
			GLuint*	 textureName   = NULL;
			BOOL	 showMines     = _flags.showMines;
			BOOL	 showGoodFlags = _flags.showGoodFlags;
			GLdouble cellWidth     = _surfaceSize.width  / (GLdouble)_values.width;
			GLdouble cellHeight    = _surfaceSize.height / (GLdouble)_values.height;
			zuint	 colorIndex;

			glEnableClientState(GL_VERTEX_ARRAY);
			glMatrixMode(GL_MODELVIEW);
			glLoadIdentity();

			if (_flags.flat)
				{
				GLfloat *palette[2] = {_cellColors1, _cellColors2};
				NSInteger paletteIndex = 0;

				for (y = 0; y < _values.height; y++)
					{
					for (x = 0; x < _values.width; x++, paletteIndex = !paletteIndex)
						{
						cell = minesweeper_cell(&_game, z_2d_type(SIZE)(x, y));

						if (CELL_IS(DISCLOSED))
							{
							if (CELL_IS(EXPLODED))
								{
								colorIndex = kThemeColorKeyMine;
								textureName = &_textureNames[kTextureIndexExplosion];
								}

							else if (CELL_IS(WARNING))
								{
								colorIndex = kThemeColorKeyWarning;
								textureName = &_textureNames[CELL_WARNING - 1];
								}

							else colorIndex = kThemeColorKeyClean;

							glColor3fv(_cellColors1[colorIndex]);
							}

						else	{
							if (CELL_IS(FLAG))
								{
								colorIndex = (_state != kBoardStateGame && CELL_IS(MINE) && showGoodFlags)
									 ? kThemeColorKeyConfirmedFlag
									 : kThemeColorKeyFlag;

								textureName = &_textureNames[kTextureIndexFlag];
								}

							else	{
								colorIndex = kThemeColorKeyCovered;

								if (showMines && CELL_IS(MINE))
									textureName = &_textureNames[kTextureIndexMine];

								glColor3fv(&palette[paletteIndex][colorIndex * 3]);
								}
							}

						glPushMatrix();
						glTranslated(cellX = cellWidth * (GLdouble)x, cellY = cellHeight * (GLdouble)y, 0.0);
						glScaled(cellWidth, cellHeight, 1.0);
						glBindTexture(GL_TEXTURE_2D, 0);
						glVertexPointer(2, GL_DOUBLE, 0, cellVertices);
						glDrawArrays(GL_QUADS, 0, 4);
						glPopMatrix();

						if (textureName != NULL)
							{
							//SET_COLOR(Warning);
							glPushMatrix();
							glTranslated(ceil(cellX), ceil(cellY), 0.0);
							glScaled(_textureSize, _textureSize, 1.0);
							glBindTexture(GL_TEXTURE_2D, *textureName);
							glBegin(GL_QUADS);
								glTexCoord2d(0.0, 0.0); glVertex2d(0.0,	1.0);
								glTexCoord2d(1.0, 0.0); glVertex2d(1.0, 1.0);
								glTexCoord2d(1.0, 1.0); glVertex2d(1.0, 0.0);
								glTexCoord2d(0.0, 1.0); glVertex2d(0.0, 0.0);
							glEnd();
							glPopMatrix();
							textureName = NULL;
							}
						}

					if (!(_values.width & 1)) paletteIndex = !paletteIndex;
					}
				}

			else for (y = 0; y < _values.height; y++) for (x = 0; x < _values.width; x++)
				{
				cell = minesweeper_cell(&_game, z_2d_type(SIZE)(x, y));

				if (CELL_IS(DISCLOSED))
					{
					if (CELL_IS(EXPLODED))
						{
						colorIndex = kThemeColorKeyMine;
						textureName = &_textureNames[kTextureIndexExplosion];
						}

					else if (CELL_IS(WARNING))
						{
						colorIndex = kThemeColorKeyWarning;
						textureName = &_textureNames[CELL_WARNING - 1];
						}

					else colorIndex = kThemeColorKeyClean;
					}

				else	{
					if (CELL_IS(FLAG))
						{
						colorIndex = (_state != kBoardStateGame && CELL_IS(MINE) && showGoodFlags)
							? kThemeColorKeyConfirmedFlag
							: kThemeColorKeyFlag;

						textureName = &_textureNames[kTextureIndexFlag];
						}

					else	{
						if (showMines && CELL_IS(MINE))
							textureName = &_textureNames[kTextureIndexMine];

						colorIndex = kThemeColorKeyCovered;
						}
					}

				glColor3fv(_cellColors1[colorIndex]);

				glPushMatrix();
				glTranslated(cellX = cellWidth * (GLdouble)x, cellY = cellHeight * (GLdouble)y, 0.0);
				glScaled(cellWidth, cellHeight, 1.0);
				glBindTexture(GL_TEXTURE_2D, 0);
				glVertexPointer(2, GL_DOUBLE, 0, cellVertices);
				glDrawArrays(GL_QUADS, 0, 4);

				if (!CELL_IS(DISCLOSED)) for (zuint edgeIndex = 0; edgeIndex < 4; edgeIndex++)
					{
					glColor3fv(_cellColors2[colorIndex][edgeIndex]);
					glVertexPointer(2, GL_DOUBLE, 0, &cellEdgeVertices[edgeIndex][0]);
					glDrawArrays(GL_QUADS, 0, 4);
					}

				glPopMatrix();

				if (textureName != NULL)
					{
					//SET_COLOR(Warning);
					glPushMatrix();
					glTranslated(ceil(cellX), ceil(cellY), 0.0);
					glScaled(_textureSize, _textureSize, 1.0);
					glBindTexture(GL_TEXTURE_2D, *textureName);
					glBegin(GL_QUADS);
						glTexCoord2d(0.0, 0.0); glVertex2d(0.0,	1.0);
						glTexCoord2d(1.0, 0.0); glVertex2d(1.0, 1.0);
						glTexCoord2d(1.0, 1.0); glVertex2d(1.0, 0.0);
						glTexCoord2d(0.0, 1.0); glVertex2d(0.0, 0.0);
					glEnd();
					glPopMatrix();
					textureName = NULL;
					}
				}

			glDisable(GL_TEXTURE_2D);
			glDisable(GL_BLEND);
			}

		[[self openGLContext] flushBuffer];
		}


	- (void) reshape
		{
		if (_game.state > MINESWEEPER_STATE_INITIALIZED)
			{
			[[self openGLContext] makeCurrentContext];
			/*CGLError error = 0;
			CGLContextObj context = CGLGetCurrentContext();*/
 
/*			// Enable the multi-threading
			error = CGLEnable(context, kCGLCEMPEngine);
 
			if (error != kCGLNoError)
				{
				NSLog(@"OpenGL mutithreading not available");
				// Multi-threaded execution is possibly not available
				// Insert your code to take appropriate action
				}*/

			_surfaceSize = [self respondsToSelector: @selector(convertSizeToBacking:)]
				? [self convertSizeToBacking: self.bounds.size]
				: self.bounds.size;

			_textureSize = floor(_surfaceSize.width / (CGFloat)_values.width);

			//----------------------------------------------.
			// Destruimos las texturas actuales si existen. |
			//----------------------------------------------'
			if (_flags.texturesCreated) glDeleteTextures(11, _textureNames);

			//------------------------------------------------.
			// Avisamos de que las texturas han sido creadas. |
			//------------------------------------------------'
			_flags.texturesCreated = YES;

			//------------------------------------------------.
			// Creamos nuevas texturas para el tamaño actual. |
			//------------------------------------------------'
			[self setTextureGraphicContext];
			[self createNumberTextures];
			[self createImageTextures];
			[NSGraphicsContext restoreGraphicsState];

			//---------------------------------------.
			// Configuramos la proyección de OpenGL. |
			//---------------------------------------'
			glViewport(0, 0, _surfaceSize.width, _surfaceSize.height);
			glMatrixMode(GL_PROJECTION);
			glLoadIdentity();
			glOrtho(0.0, _surfaceSize.width, 0.0, _surfaceSize.height, -1.0, 1.0);
			glMatrixMode(GL_MODELVIEW);
			glLoadIdentity();
			}
		}


	- (void) mouseDown: (NSEvent *) event
		{_coordinates = [self cellCoordinatesOfEvent: event];}


	- (void) rightMouseDown: (NSEvent *) event
		{_coordinates = [self cellCoordinatesOfEvent: event];}


	- (void) mouseUp: (NSEvent *) event
		{
		if (	_state == kBoardStateGame &&
			z_2d_type_are_equal(SIZE)(_coordinates, [self cellCoordinatesOfEvent: event])
		)
			{
			if ([event clickCount] > 1 || _leftButtonAction == kBoardButtonActionReveal)
				[self revealRemaining];

			else if (_leftButtonAction == kBoardButtonActionFlag) [self toggleFlag];

			else [self discloseCell];
			}
		}


	- (void) rightMouseUp: (NSEvent *) event
		{
		if (	_state == kBoardStateGame &&
			z_2d_type_are_equal(SIZE)(_coordinates, [self cellCoordinatesOfEvent: event])
		)
			[self toggleFlag];
		}


#	pragma mark - Public


	- (void) setTheme: (Theme	   *) theme
		 images:   (NSMutableArray *) images
		{
		_theme.owner = nil;
		[_theme release];
		(_theme = [theme retain]).owner = self;
		_flags.flat = theme.flat;
		_cellBrightnessDelta  = theme.cellBrightnessDelta;
		for (NSUInteger key = 0; key < 6; key++) [self updateCellColorsForKey: key];
		//for (NSUInteger key = 0; key < 3; key++) [self update: key];

		if (images && images != _themeImages)
			{
			[_themeImages release];
			_themeImages = [images retain];

			if (_game.state > MINESWEEPER_STATE_INITIALIZED)
				{
				if (_flags.texturesCreated) glDeleteTextures(11, _textureNames);
				[self setTextureGraphicContext];
				[self createNumberTextures];
				[self createImageTextures];
				[NSGraphicsContext restoreGraphicsState];
				self.needsDisplay = YES;
				}
			}
		}


	- (void) didChangeThemeProperty: (uint8_t) property
		 valueAtIndex:		 (uint8_t) index
		{
		switch (property)
			{
			case kThemePropertyGrid:
			case kThemePropertyGridColor:
			case kThemePropertyCellBorder:
			case kThemePropertyMineCellBorder:
			case kThemePropertyMineCellBorder:
			case kThemePropertyCellBorderSize:
			case kThemePropertyAlternateCoveredCells:
			case kThemePropertyAlternateUncoveredCells:
			case kThemePropertyCellBrightnessDelta:
			case kThemePropertyCellColor:
			case kThemePropertyNumberColor:
			case kThemePropertyNumberFontName:
			case kThemePropertyNumberFontScale:
			case kThemePropertyImage:
			case kThemePropertyImageColor:
			default: break;
			}
		}


	- (void) newGameWithValues: (GameValues) values
		{
		GameValues oldValues = _values;

		minesweeper_prepare(&_game, z_2d_type(SIZE)(values.width, values.height), values.mineCount);
		_values = values;
		_state = kBoardStateGame;

		if (values.width != oldValues.width || values.height != oldValues.height)
			self.bounds = self.bounds;

		self.needsDisplay = YES;
		}


	- (void) restart
		{
		minesweeper_prepare
			(&_game, z_2d_type(SIZE)(_values.width, _values.height),
			 minesweeper_mine_count(&_game));

		_state = kBoardStateGame;
		self.needsDisplay = YES;
		}


	- (BOOL) hintCoordinates: (Z2DSize *) coordinates
		{return minesweeper_hint(&_game, coordinates);}


	- (void) discloseHintCoordinates: (Z2DSize) coordinates
		{
		minesweeper_disclose(&_game, coordinates);

		if (_game.state == MINESWEEPER_STATE_SOLVED)
			{
			_state = kBoardStateResolved;
			minesweeper_flag_all_mines(&_game);
			}

		self.needsDisplay = YES;
		}


	- (size_t) snapshotSize
		{return (size_t)minesweeper_snapshot_size(&_game);}


	- (void) snapshot: (void *) output
		{minesweeper_snapshot(&_game, output);}


	- (void) setSnapshot: (void *) snapshot
		 ofSize:      (size_t) snapshotSize
		{
		minesweeper_set_snapshot(&_game, snapshot, snapshotSize);

		Z2DSize size = minesweeper_size(&_game);
		_values.width	  = size.x;
		_values.height	  = size.y;
		_values.mineCount = minesweeper_mine_count(&_game);

		if ((_state = _game.state) == MINESWEEPER_STATE_PRISTINE)
			_state = kBoardStateGame;

		self.bounds	  = self.bounds;
		self.needsDisplay = YES;
		}


	- (NSRect) frameForCoordinates: (Z2DSize) coordinates
		{
		NSSize size = self.bounds.size;

		NSSize cellSize = NSMakeSize
			(size.width  / (CGFloat)_values.width,
			 size.height / (CGFloat)_values.height);

		return NSMakeRect
			(cellSize.width	 * (CGFloat)coordinates.x,
			 cellSize.height * (CGFloat)coordinates.y,
			 cellSize.width, cellSize.height);
		}


@end

// EOF
