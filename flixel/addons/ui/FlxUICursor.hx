package flixel.addons.ui;
import flash.events.MouseEvent;
import flixel.addons.ui.Anchor;
import flixel.addons.ui.FlxUIAssets;
import flixel.addons.ui.FlxUISprite;
import flixel.addons.ui.interfaces.ICursorPointable;
import flixel.addons.ui.interfaces.IFlxUIWidget;
import flixel.FlxG;
import flixel.FlxObject;
import flixel.input.gamepad.FlxGamepadInputID;
import flixel.input.gamepad.FlxGamepad;
import flixel.input.mouse.FlxMouse;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.util.FlxDestroyUtil;

/**
 * Cursor object that you can use to "click" on interface elements using a keyboard or gamepad
 * TODO: need to support gamepad and/or deal with absence of mouse
 */
class FlxUICursor extends FlxUISprite
{
	public var callback:String->IFlxUIWidget->Void;		//callback to notify whoever's listening that I did something(presumably a FlxUI object)
	
	public var wrap:Bool=true;	//when cycling through values, loop from back to front or stop at "edges?"
	
	public var location(default, set):Int = -1;			//which object the cursor is pointing to (-1 means nothing)
	private function set_location(i:Int):Int{
		if (i >= _widgets.length) {
			i = _widgets.length - 1;
		}
		location = i;
		_updateCursor();
		return location;
	}
	
	//Key configurations, you can set easily with setDefaultKeys(KEYS_TAB), for instance.
	
	public var keysUp:Array<FlxBaseMultiInput>;    //List of keys (ie, tab) and/or key combinations (ie, shift+tab) that indicate intent to go "up"
	public var keysDown:Array<FlxBaseMultiInput>;
	public var keysLeft:Array<FlxBaseMultiInput>;
	public var keysRight:Array<FlxBaseMultiInput>;
	public var keysClick:Array<FlxBaseMultiInput>; //intent to "click" or select
	
	//Various default key configurations:
	
	public static inline var KEYS_TAB:Int =                 0x00000001; //tab to go "right", shift+tab to go "left", enter to click
	public static inline var KEYS_WASD:Int =                0x00000010; //WASD to go up/left/down/right, enter to click
	public static inline var KEYS_ARROWS:Int =              0x00000100; //Arrows to go up/left/down/right, enter to click
	public static inline var KEYS_NUMPAD:Int =              0x00001000; //Numpad numbers to go up/left/down/right, enter to click
	
	public static inline var GAMEPAD_DPAD:Int =             0x00010000; //DPAD to go up/left/down/right, A to click
	public static inline var GAMEPAD_LEFT_STICK:Int =       0x00100000; //Left STICK to go up/left/down/right, A to click
	public static inline var GAMEPAD_RIGHT_STICK:Int =      0x01000000; //Right STICK to go up/left/down/right, A to click
	public static inline var GAMEPAD_SHOULDER_BUTTONS:Int = 0x10000000; //Left / Right shoulder buttons to go left/right, A to click
	
	//Determines how the cursor attaches itself to the widget it's pointing to
	public var anchor:Anchor;
	
	public var dispatchEvents:Bool = true;                  //set to false if you just want to rely on callbacks rather than low-level events
	
	//TODO: make this work
	public var inputMethod:Int = 0x00;                      //simple bitmask for storing what input methods can move the cursor
	
	public static inline var INPUT_NONE:Int = 0x00;         //No cursor input what
	public static inline var INPUT_KEYS:Int = 0x01;         //Use keyboard to control the cursor
	public static inline var INPUT_GAMEPAD:Int = 0x10;      //Use gamepad to control the cursor
	
	/*********************************/
	
	/**
	 * Creates a cursor that can be controlled with the keyboard or gamepad
	 * @param	Callback		callback to notify listener about when something happens
	 * @param	InputMethod		bit-flag, accepts INPUT_KEYS, INPUT_GAMEPAD, or both using "|" operator
	 * @param	DefaultKeys		default hotkey layouts, accepts KEYS_TAB, ..._WASD, etc, combine using "|" operator
	 * @param	Asset			visual asset for the cursor. If not supplied, uses default
	 */
	public function new(Callback:String->IFlxUIWidget->Void,InputMethod:Int=INPUT_KEYS,DefaultKeys:Int=KEYS_TAB,?Asset:Dynamic) 
	{
		if (Asset == null) {							//No asset detected? Guess based on game's resolution
			if(FlxG.height < 400){
				Asset = FlxUIAssets.IMG_FINGER_SMALL;	//16x16 pixel finger
			}else {
				Asset = FlxUIAssets.IMG_FINGER_BIG;		//32x32 pixel finger
			}
		}
		
		super(0, 0, Asset);
		
		inputMethod = InputMethod;
		_widgets = [];
		anchor = new Anchor( -2, 0, Anchor.LEFT, Anchor.CENTER, Anchor.RIGHT, Anchor.CENTER);
		setDefaultKeys(DefaultKeys);
		callback = Callback;
		
		#if !FLX_NO_MOUSE
		if (FlxG.mouse != null && Std.is(FlxG.mouse, FlxUIMouse) == false)
		{
			_newMouse = new FlxUIMouse(FlxG.mouse.cursorContainer);
			FlxG.mouse = _newMouse;
		}
		else
		{
			_newMouse = cast FlxG.mouse;
		}
		#end
	}
	
	public override function destroy():Void {
		super.destroy();
		
		#if !FLX_NO_MOUSE
		if (FlxG.mouse == _newMouse)
		{
			//remove the local pointer, but allow the replaced mouse object to carry on, it won't hurt anything
			_newMouse = null;
		}
		#end
		
		keysUp = FlxDestroyUtil.destroyArray(keysUp);
		keysDown = FlxDestroyUtil.destroyArray(keysDown);
		keysLeft = FlxDestroyUtil.destroyArray(keysLeft);
		keysRight = FlxDestroyUtil.destroyArray(keysRight);
		keysClick = FlxDestroyUtil.destroyArray(keysClick);
		
		anchor = FlxDestroyUtil.destroy(anchor);
		
		U.clearArraySoft(_widgets);
		_widgets = null;
	}
	
	public override function update(elapsed:Float):Void {
		_clickTime += elapsed;
		super.update(elapsed);
		_checkKeys();
	}
	
	public function addWidget(widget:IFlxUIWidget):Void 
	{
		if (Std.is(widget, ICursorPointable))			//directly pointable? add it
		{
			_widgets.push(widget);
		}
		else if (Std.is(widget, FlxUIGroup))			//it's a group? 
		{			
			var g:FlxUIGroup = cast widget;
			for (member in g.members)
			{
				if (Std.is(member, IFlxUIWidget))
				{
					addWidget(cast member);					//add each member individually
				}
			}
		}
		_widgets.sort(_sortXY);
	}
	
	public function removeWidget(widget:IFlxUIWidget):Bool{
		var value:Bool = false;
		if (_widgets != null) {
			if (_widgets.indexOf(widget) != -1) {
				value = _widgets.remove(widget);
				_widgets.sort(_sortXY);
			}
		}
		return value;
	}
	
	/**
	 * Set the default key layout quickly using a constant. 
	 * @param	code	KEYS_TAB, ..._WASD, etc, combine with "|" operator
	 */
	
	public function setDefaultKeys(code:Int):Void {
		_clearKeys();
		_newKeys();
		if (code & KEYS_TAB == KEYS_TAB) {
			_addToKeys(keysRight, new FlxMultiKey(TAB, null, [SHIFT]));  //Tab, (but NOT Shift+Tab!)
			_addToKeys(keysLeft,  new FlxMultiKey(TAB, [SHIFT]));         //Shift+Tab
			_addToKeys(keysClick, new FlxMultiKey(ENTER));
		}
		if (code & KEYS_ARROWS == KEYS_ARROWS) {
			_addToKeys(keysRight, new FlxMultiKey(RIGHT));
			_addToKeys(keysLeft,  new FlxMultiKey(LEFT));
			_addToKeys(keysDown,  new FlxMultiKey(DOWN));
			_addToKeys(keysUp,    new FlxMultiKey(UP));
			_addToKeys(keysClick, new FlxMultiKey(ENTER));
		}
		if (code & KEYS_WASD == KEYS_WASD) {
			_addToKeys(keysRight, new FlxMultiKey(D));
			_addToKeys(keysLeft,  new FlxMultiKey(A));
			_addToKeys(keysDown,  new FlxMultiKey(S));
			_addToKeys(keysUp,    new FlxMultiKey(W));
			_addToKeys(keysClick, new FlxMultiKey(ENTER));
		}
		if (code & KEYS_NUMPAD == KEYS_NUMPAD) {
			_addToKeys(keysRight, new FlxMultiKey(NUMPADSIX));
			_addToKeys(keysLeft,  new FlxMultiKey(NUMPADFOUR));
			_addToKeys(keysDown,  new FlxMultiKey(NUMPADTWO));
			_addToKeys(keysUp,    new FlxMultiKey(NUMPADEIGHT));
			_addToKeys(keysClick, new FlxMultiKey(ENTER));
		}
		
		#if !FLX_NO_GAMEPAD
		if (code & GAMEPAD_DPAD == GAMEPAD_DPAD) {
			var gamepad = getGamepad();
			_addToKeys(keysLeft,  new FlxMultiGamepad(gamepad, FlxGamepadInputID.DPAD_LEFT));
			_addToKeys(keysRight, new FlxMultiGamepad(gamepad, FlxGamepadInputID.DPAD_RIGHT));
			_addToKeys(keysDown,  new FlxMultiGamepad(gamepad, FlxGamepadInputID.DPAD_DOWN));
			_addToKeys(keysUp,    new FlxMultiGamepad(gamepad, FlxGamepadInputID.DPAD_UP));
			_addToKeys(keysClick, new FlxMultiGamepad(gamepad, FlxGamepadInputID.A));
		}
		if (code & GAMEPAD_SHOULDER_BUTTONS == GAMEPAD_SHOULDER_BUTTONS) {
			var gamepad = getGamepad();
			_addToKeys(keysLeft,  new FlxMultiGamepad(gamepad, FlxGamepadInputID.LEFT_SHOULDER));
			_addToKeys(keysRight, new FlxMultiGamepad(gamepad, FlxGamepadInputID.RIGHT_SHOULDER));
			_addToKeys(keysClick, new FlxMultiGamepad(gamepad, FlxGamepadInputID.A));
		}
		if (code & GAMEPAD_LEFT_STICK == GAMEPAD_LEFT_STICK) {
			var gamepad = getGamepad();
			_addToKeys(keysLeft,  new FlxMultiGamepadAnalogStick(gamepad, {id:LEFT_ANALOG_STICK, axis:X, positive:false}));
			_addToKeys(keysRight, new FlxMultiGamepadAnalogStick(gamepad, {id:LEFT_ANALOG_STICK, axis:X, positive:true}));
			_addToKeys(keysUp,    new FlxMultiGamepadAnalogStick(gamepad, {id:LEFT_ANALOG_STICK, axis:Y, positive:false}));
			_addToKeys(keysDown,  new FlxMultiGamepadAnalogStick(gamepad, {id:LEFT_ANALOG_STICK, axis:Y, positive:true}));
			_addToKeys(keysClick, new FlxMultiGamepad(gamepad, FlxGamepadInputID.A));
		}
		if (code & GAMEPAD_RIGHT_STICK == GAMEPAD_RIGHT_STICK) {
			var gamepad = getGamepad();
			_addToKeys(keysLeft,  new FlxMultiGamepadAnalogStick(gamepad, {id:RIGHT_ANALOG_STICK, axis:X, positive:false}));
			_addToKeys(keysRight, new FlxMultiGamepadAnalogStick(gamepad, {id:RIGHT_ANALOG_STICK, axis:X, positive:true}));
			_addToKeys(keysUp,    new FlxMultiGamepadAnalogStick(gamepad, {id:RIGHT_ANALOG_STICK, axis:Y, positive:false}));
			_addToKeys(keysDown,  new FlxMultiGamepadAnalogStick(gamepad, {id:RIGHT_ANALOG_STICK, axis:Y, positive:true}));
			_addToKeys(keysClick, new FlxMultiGamepad(gamepad, FlxGamepadInputID.A));
		}
		#end
	}
	
	/****PRIVATE****/
	
	private var _widgets:Array<IFlxUIWidget>;			//master list of widgets under cursor's control
	#if !FLX_NO_MOUSE
	private var _newMouse:FlxUIMouse;
	#end
	private var _clickPressed:Bool = false;
	
	private var _clickTime:Float = 0;
	
	#if !FLX_NO_GAMEPAD
	private function getGamepad():FlxGamepad
	{
		var gamepad = FlxG.gamepads.getFirstActiveGamepad();
		if (gamepad == null)
		{
			for (i in 0...FlxG.gamepads.numActiveGamepads)
			{
				gamepad = FlxG.gamepads.getByID(i);
				if (gamepad != null)
				{
					return gamepad;
				}
			}
		}
		return gamepad;
	}
	#end
	
	private function _sortXY(a:IFlxUIWidget, b:IFlxUIWidget):Int {
		if (a.y < b.y) return -1;
		if (a.y > b.y) return 1;
		if (a.x < b.x) return -1;
		if (a.x > b.x) return 1;
		return 0;
	}
	
	private function _addToKeys(keys:Array<FlxBaseMultiInput>, m:FlxBaseMultiInput) {
		var mk:FlxBaseMultiInput;
		var exists:Bool = false;
		for (mk in keys) {
			if (m.equals(mk)) {
				exists = true;
				break;
			}
		}
		if (!exists) {
			keys.push(m);
		}
	}
	
	private function _clearKeys():Void {
		U.clearArray(keysUp); keysUp = null;
		U.clearArray(keysDown); keysDown = null;
		U.clearArray(keysLeft); keysLeft = null;
		U.clearArray(keysRight); keysRight = null;
		U.clearArray(keysClick); keysClick = null;
	}
	
	private function _newKeys():Void {
		keysUp = [];
		keysDown = [];
		keysLeft = [];
		keysRight = [];
		keysClick = [];
	}
	
	private function _checkKeys():Void {
		var key:FlxBaseMultiInput;
		
		var upPressed:Bool = false;
		
		for (key in keysUp) {
			if (key.justPressed()) {
				_doInput(0, -1);
				break;
			}
		}
		for (key in keysDown) {
			if (key.justPressed()) {
				_doInput(0, 1);
				break;
			}
		}
		for (key in keysLeft) {
			if (key.justPressed()) {
				_doInput( -1, 0);
				break;
			}
		}
		for (key in keysRight) {
			if (key.justPressed()) {
				_doInput(1, 0);
				break;
			}
		}
		
		if (_clickKeysJustPressed())		//JUST PRESSED: send a press event only the first time it's pressed
		{
			_clickPressed = true;
			_clickTime = 0;
			_doPress();
		}
		
		if (_clickKeysPressed())			//STILL PRESSED: keep the cursor in that position while the key is down
		{
			_clickPressed = true;
			_doMouseMove();
		}
		else if(_clickTime > 0)				//NOT PRESSED and not exact same frame as when it was just pressed
		{
			if (_clickPressed)				//if we were previously just pressed...
			{
				_clickPressed = false;		//count this as "just released"
				_doRelease();				//do the release action
			}
		}
	}
	
	private function _clickKeysJustPressed():Bool
	{
		for (key in keysClick)
		{
			if (key.justPressed())
			{
				return true;
			}
		}
		return false;
	}
	
	private function _clickKeysPressed():Bool
	{
		for (key in keysClick)
		{
			if (key.pressed())
			{
				return true;
			}
		}
		return false;
	}
	
	private function _getWidgetPoint():FlxPoint {
		//get the widget;
		var currWidget:IFlxUIWidget = _widgets[location];
		if (currWidget == null) {
			return null;
		}
		
		var fo:FlxObject;
		var widgetPoint:FlxPoint;
		
		//Try to convert to FlxObject if possible
		if (Std.is(currWidget, FlxObject)) {
			fo = cast currWidget;
			//success! Get ScreenXY, to deal with any possible scrolling/camera craziness
			widgetPoint = fo.getScreenPosition();
		}else {
			//otherwise just make your best guess from current raw position
			widgetPoint = FlxPoint.get(currWidget.x, currWidget.y);
		}
		
		//get center point of object
		widgetPoint.x += currWidget.width / 2;
		widgetPoint.y += currWidget.height / 2;
		
		return widgetPoint;
	}
	
	private function _doMouseMove(?pt:FlxPoint):Void {
		var dispose:Bool = false;
		if (pt == null) {
			pt = _getWidgetPoint();
			if (pt == null)
			{
				return;
			}
			dispose = true;
		}
		if (dispatchEvents) {
			//dispatch a low-level mouse event to the FlxG.stage object itself
			
			var rawMouseX:Int = Std.int(pt.x * FlxG.camera.zoom);
			var rawMouseY:Int = Std.int(pt.y * FlxG.camera.zoom);
			
			#if !FLX_NO_MOUSE
			//REALLY force it to this location
			FlxG.mouse.setGlobalScreenPositionUnsafe(rawMouseX, rawMouseY);
			if (_newMouse != null)
			{
				_newMouse.updateGlobalScreenPosition = false;	//don't low-level-update the mouse while I'm overriding the mouse position
			}
			#end
			
			#if !FLX_NO_KEYBOARD
			FlxG.stage.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_MOVE, true, false, rawMouseX, rawMouseY, FlxG.stage, FlxG.keys.pressed.CONTROL, FlxG.keys.pressed.ALT, FlxG.keys.pressed.SHIFT));
			#end
		}
		if (dispose) {
			pt.put();
		}
	}
	
	private function _doPress(?pt:FlxPoint):Void {
		var currWidget:IFlxUIWidget = _widgets[location];
		if (currWidget == null) {
			return null;
		}
		
		var dispose:Bool = false;
		if (pt == null) {
			pt = _getWidgetPoint();
			if (pt == null)
			{
				return;
			}
			dispose = true;
		}
		
		var rawMouseX:Float = pt.x * FlxG.camera.zoom;
		var rawMouseY:Float = pt.y * FlxG.camera.zoom;
		
		#if !FLX_NO_KEYBOARD
		if (dispatchEvents) {
			//dispatch a low-level mouse event to the FlxG.stage object itself
			FlxG.stage.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_DOWN, true, false, rawMouseX, rawMouseY, FlxG.stage, FlxG.keys.pressed.CONTROL, FlxG.keys.pressed.ALT, FlxG.keys.pressed.SHIFT));
		}
		#end
		
		if (callback != null) {
			//notify the listener that we just "pressed" the widget
			callback("cursor_down", currWidget);
		}
		if (dispose) {
			pt.put();
		}
	}
	
	private function _doRelease(?pt:FlxPoint):Void {
		var currWidget:IFlxUIWidget = _widgets[location];
		if (currWidget == null) {
			return null;
		}
		
		var dispose:Bool = false;
		if (pt == null) {
			pt = _getWidgetPoint();
			if (pt == null)
			{
				return;
			}
			dispose = true;
		}
		
		var rawMouseX:Float = pt.x * FlxG.camera.zoom;
		var rawMouseY:Float = pt.y * FlxG.camera.zoom;
		
		#if !FLX_NO_KEYBOARD
		if (dispatchEvents)
		{
			//dispatch a low-level mouse event to the FlxG.stage object itself
			FlxG.stage.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_UP, true, false, rawMouseX, rawMouseY, FlxG.stage, FlxG.keys.pressed.CONTROL, FlxG.keys.pressed.ALT, FlxG.keys.pressed.SHIFT));
			if (_clickPressed)
			{
				FlxG.stage.dispatchEvent(new MouseEvent(MouseEvent.CLICK, true, false, rawMouseX, rawMouseY, FlxG.stage, FlxG.keys.pressed.CONTROL, FlxG.keys.pressed.ALT, FlxG.keys.pressed.SHIFT));
			}
		}
		#end
		
		if (callback != null) {
			//notify the listener that we just "clicked" the widget
			callback("cursor_click", currWidget);
		}
		if (dispose) {
			pt.put();
		}
		
		#if !FLX_NO_MOUSE
		if (_newMouse != null)
		{
			_newMouse.updateGlobalScreenPosition = true;	//resume low-level-mouse updating now that I'm done overriding it
			_newMouse.setGlobalScreenPositionUnsafe(Std.int(FlxG.game.mouseX), Std.int(FlxG.game.mouseY));
		}
		#end
	}
	
	private function _doInput(X:Int, Y:Int):Void {
		var currWidget:IFlxUIWidget=null;
		
		if (Y == 0) {											//just move back/forth
			//Easy: go to the next index in the array, loop around if needed
			if (location + X < 0) {
				if (wrap) 
				{
					location = (location + X) + _widgets.length;
				}
			}else if (location + X >= _widgets.length){
				if (wrap)
				{
					location = (location + X) - _widgets.length;
				}
			}else{
				location = location + X;
			}
			currWidget = _widgets[location];
		}else {													//move UP/DOWN
			//Harder: iterate through array, looking for widget with higher or lower y value
			
			currWidget = _widgets[location];
			
			var nextWidget:IFlxUIWidget = null;
			
			var dx:Float = Math.POSITIVE_INFINITY;
			var dy:Float = Math.POSITIVE_INFINITY;
			
			var bestdx:Float = dx;
			var bestdy:Float = dy;
			
			var bestWidget:IFlxUIWidget = null;
			var besti:Int = -1;
			
			//DESIRED BEHAVIOR: Jump to the CLOSEST OBJECT that ALSO:
			//is located ABOVE/BELOW me (depending on Y's sign)
			
			for (i in 0..._widgets.length)
			{
				if (i != location)
				{
					nextWidget = _widgets[i];							//Check each widget
					dy = nextWidget.y - currWidget.y;					//Get y distance
					if (FlxMath.sameSign(dy, Y) && dy != 0)				//If it's in the right direction, and not at same Y, consider it
					{
						dy = Math.abs(dy);
						if (dy < bestdy)								//If abs. y distance is closest so far
						{
							bestdy = dy;
							bestdx = Math.abs(currWidget.x-nextWidget.x);	//reset this every time a better dy is found
							besti = i;
						}
						else if (dy == bestdy)
						{
							dx = Math.abs(currWidget.x - nextWidget.x);		//If abs. x distance is closest so far
							if (dx < bestdx)
							{
								bestdx = dx;
								besti = i;
							}
						}
					}
				}
			}
			
			if (besti != -1)
			{
				location = besti;
				currWidget = _widgets[besti];
			}
			else						//didn't find anything
			{
				if (wrap)				//try wrapping around
				{
					bestdx = Math.POSITIVE_INFINITY;
					bestdy = 0;							//Now we want the FURTHEST object from us
					for (i in 0..._widgets.length)
					{
						if (i != location)
						{
							nextWidget = _widgets[i];
							dy = nextWidget.y - currWidget.y;
							if (FlxMath.sameSign(dy, Y) == false && dy != 0) {	//I want the WRONG direction this time
								dy = Math.abs(dy);
								if (dy > bestdy)
								{
									bestdy = dy;
									bestdx = Math.abs(currWidget.x - nextWidget.x);
									besti = i;
								}
								else if (dy == bestdy)
								{
									dx = Math.abs(currWidget.x - nextWidget.x);
									if (dx < bestdx)
									{
										bestdx = dx;
										besti = i;
									}
								}
							}
						}
					}
				}
				if (besti != -1)
				{
					location = besti;
					currWidget = _widgets[besti];
				}
			}
		}
		
		if (callback != null) {
			//notify the listener that the cursor has moved
			callback("cursor_jump", currWidget);
		}
	}
	
	private function _updateCursor():Void {
		if (location < 0)
		{
			visible = false;
			return;
		}
		
		visible = true;
		
		var currWidget:IFlxUIWidget = _widgets[location];
		if (currWidget != null) {
			anchor.anchorThing(this, cast currWidget);
		}
	}
}