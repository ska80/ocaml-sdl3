#include "sdl3_stubs.h"

/* Mouse button conversions shared by event decoding and state queries. */

/* Sdl3.Mouse.button constant constructor order. */
static const Uint8 mouse_buttons[] = {SDL_BUTTON_LEFT, SDL_BUTTON_MIDDLE, SDL_BUTTON_RIGHT,
                                      SDL_BUTTON_X1, SDL_BUTTON_X2};

static value mouse_button_value(Uint8 button) {
    for (size_t i = 0; i < sizeof(mouse_buttons) / sizeof(mouse_buttons[0]); ++i)
        if (mouse_buttons[i] == button) return Val_int(i);
    return caml_alloc_1(0, Val_int(button)); /* Other */
}

CAMLprim value osdl_mouse_pressed(value buttons, value button) {
    intnat index = Is_long(button) ? mouse_buttons[Int_val(button)] : Long_val(Field(button, 0));
    if (index < 1 || index > 32) return Val_false;
    return Val_bool(((Uint32)Int32_val(buttons) & SDL_BUTTON_MASK(index)) != 0);
}

/* Sdl3.Gamepad.axis and Gamepad.button constructor order. */
static const SDL_GamepadAxis gamepad_axes[] = {
    SDL_GAMEPAD_AXIS_LEFTX,  SDL_GAMEPAD_AXIS_LEFTY,        SDL_GAMEPAD_AXIS_RIGHTX,
    SDL_GAMEPAD_AXIS_RIGHTY, SDL_GAMEPAD_AXIS_LEFT_TRIGGER, SDL_GAMEPAD_AXIS_RIGHT_TRIGGER,
};

static const SDL_GamepadButton gamepad_buttons[] = {
    SDL_GAMEPAD_BUTTON_SOUTH,          SDL_GAMEPAD_BUTTON_EAST,
    SDL_GAMEPAD_BUTTON_WEST,           SDL_GAMEPAD_BUTTON_NORTH,
    SDL_GAMEPAD_BUTTON_BACK,           SDL_GAMEPAD_BUTTON_GUIDE,
    SDL_GAMEPAD_BUTTON_START,          SDL_GAMEPAD_BUTTON_LEFT_STICK,
    SDL_GAMEPAD_BUTTON_RIGHT_STICK,    SDL_GAMEPAD_BUTTON_LEFT_SHOULDER,
    SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER, SDL_GAMEPAD_BUTTON_DPAD_UP,
    SDL_GAMEPAD_BUTTON_DPAD_DOWN,      SDL_GAMEPAD_BUTTON_DPAD_LEFT,
    SDL_GAMEPAD_BUTTON_DPAD_RIGHT,     SDL_GAMEPAD_BUTTON_MISC1,
    SDL_GAMEPAD_BUTTON_RIGHT_PADDLE1,  SDL_GAMEPAD_BUTTON_LEFT_PADDLE1,
    SDL_GAMEPAD_BUTTON_RIGHT_PADDLE2,  SDL_GAMEPAD_BUTTON_LEFT_PADDLE2,
    SDL_GAMEPAD_BUTTON_TOUCHPAD,       SDL_GAMEPAD_BUTTON_MISC2,
    SDL_GAMEPAD_BUTTON_MISC3,          SDL_GAMEPAD_BUTTON_MISC4,
    SDL_GAMEPAD_BUTTON_MISC5,          SDL_GAMEPAD_BUTTON_MISC6,
};

CAMLprim value osdl_gamepad_has_axis(value gamepad, value axis) {
    return Val_bool(SDL_GamepadHasAxis(osdl_live(gamepad), gamepad_axes[Int_val(axis)]));
}

CAMLprim value osdl_gamepad_has_button(value gamepad, value button) {
    return Val_bool(SDL_GamepadHasButton(osdl_live(gamepad), gamepad_buttons[Int_val(button)]));
}

CAMLprim value osdl_gamepad_axis(value gamepad, value axis) {
    return Val_int(SDL_GetGamepadAxis(osdl_live(gamepad), gamepad_axes[Int_val(axis)]));
}

CAMLprim value osdl_gamepad_button(value gamepad, value button) {
    return Val_bool(SDL_GetGamepadButton(osdl_live(gamepad), gamepad_buttons[Int_val(button)]));
}

/* Touch device queries and finger values. */

static void osdl_require_touch_context(value context) {
    osdl_require_subsystem(context, SDL_INIT_VIDEO, "Start SDL with Video to query touch devices");
}

CAMLprim value osdl_touch_devices(value context, value snapshot) {
    CAMLparam2(context, snapshot);
    CAMLlocal2(list, id);

    osdl_require_touch_context(context);

    int          count;
    SDL_TouchID* ids = SDL_GetTouchDevices(&count);
    osdl_publish(snapshot, ids, "SDL_GetTouchDevices");

    list = Val_emptylist;
    for (int i = count; i > 0; --i) {
        id   = caml_copy_int64((int64_t)ids[i - 1]);
        list = caml_alloc_2(0, id, list);
    }
    CAMLreturn(list);
}

CAMLprim value osdl_touch_name(value context, value id) {
    osdl_require_touch_context(context);

    const char* name = SDL_GetTouchDeviceName((SDL_TouchID)Int64_val(id));
    if (!name) osdl_fail("SDL_GetTouchDeviceName");
    return caml_copy_string(name);
}

CAMLprim value osdl_touch_device_type(value context, value id) {
    osdl_require_touch_context(context);

    SDL_TouchDeviceType type = SDL_GetTouchDeviceType((SDL_TouchID)Int64_val(id));
    switch (type) {
    case SDL_TOUCH_DEVICE_DIRECT:
        return Val_int(0);
    case SDL_TOUCH_DEVICE_INDIRECT_ABSOLUTE:
        return Val_int(1);
    case SDL_TOUCH_DEVICE_INDIRECT_RELATIVE:
        return Val_int(2);
    case SDL_TOUCH_DEVICE_INVALID:
        osdl_fail("SDL_GetTouchDeviceType");
    default:
        return caml_alloc_1(0, osdl_val_int(type)); /* Other */
    }
}

static value finger_value(SDL_FingerID id, float x, float y, float pressure) {
    CAMLparam0();
    CAMLlocal4(v_id, v_x, v_y, v_pressure);

    v_id       = caml_copy_int64((int64_t)id);
    v_x        = caml_copy_double(x);
    v_y        = caml_copy_double(y);
    v_pressure = caml_copy_double(pressure);
    CAMLreturn(caml_alloc_4(0, v_id, v_x, v_y, v_pressure));
}

CAMLprim value osdl_touch_fingers(value context, value id, value snapshot) {
    CAMLparam3(context, id, snapshot);
    CAMLlocal2(list, finger);

    osdl_require_touch_context(context);

    int          count;
    SDL_Finger** fingers = SDL_GetTouchFingers((SDL_TouchID)Int64_val(id), &count);
    osdl_publish(snapshot, fingers, "SDL_GetTouchFingers");

    list = Val_emptylist;
    for (int i = count; i > 0; --i) {
        const SDL_Finger* f = fingers[i - 1];
        finger              = finger_value(f->id, f->x, f->y, f->pressure);
        list                = caml_alloc_2(0, finger, list);
    }
    CAMLreturn(list);
}

/* Event decoding. */

/* Sdl3.Event.kind block constructor tags. Quit is an immediate. */
enum {
    K_WINDOW,
    K_KEY,
    K_TEXT_INPUT,
    K_TEXT_EDITING,
    K_MOUSE_MOTION,
    K_MOUSE_BUTTON,
    K_MOUSE_WHEEL,
    K_GAMEPAD_ADDED,
    K_GAMEPAD_REMOVED,
    K_GAMEPAD_REMAPPED,
    K_GAMEPAD_AXIS,
    K_GAMEPAD_BUTTON,
    K_DISPLAY,
    K_TOUCH,
    K_DROP,
    K_OTHER,
};

/* Sdl3.Event.window_change counts constants and blocks separately. */
static value window_event_value(const SDL_WindowEvent* event) {
    CAMLparam0();
    CAMLlocal2(window, change);

    switch (event->type) {
    case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
        change = Val_int(0);
        break;
    case SDL_EVENT_WINDOW_FOCUS_GAINED:
        change = Val_int(1);
        break;
    case SDL_EVENT_WINDOW_FOCUS_LOST:
        change = Val_int(2);
        break;
    case SDL_EVENT_WINDOW_RESIZED:
        change = caml_alloc_2(0, osdl_val_int(event->data1), osdl_val_int(event->data2));
        break;
    case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
        change = caml_alloc_2(1, osdl_val_int(event->data1), osdl_val_int(event->data2));
        break;
    case SDL_EVENT_WINDOW_MOVED:
        change = caml_alloc_2(2, osdl_val_int(event->data1), osdl_val_int(event->data2));
        break;
    case SDL_EVENT_WINDOW_DISPLAY_CHANGED:
        change = caml_alloc_1(3, caml_copy_int32(event->data1));
        break;
    case SDL_EVENT_WINDOW_SHOWN:
        change = Val_int(3);
        break;
    case SDL_EVENT_WINDOW_HIDDEN:
        change = Val_int(4);
        break;
    case SDL_EVENT_WINDOW_MINIMIZED:
        change = Val_int(5);
        break;
    case SDL_EVENT_WINDOW_MAXIMIZED:
        change = Val_int(6);
        break;
    case SDL_EVENT_WINDOW_RESTORED:
        change = Val_int(7);
        break;
    case SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED:
        change = Val_int(8);
        break;
    case SDL_EVENT_WINDOW_ENTER_FULLSCREEN:
        change = Val_int(9);
        break;
    case SDL_EVENT_WINDOW_LEAVE_FULLSCREEN:
        change = Val_int(10);
        break;
    case SDL_EVENT_WINDOW_MOUSE_ENTER:
        change = Val_int(11);
        break;
    case SDL_EVENT_WINDOW_MOUSE_LEAVE:
        change = Val_int(12);
        break;
    default:
        CAMLreturn(caml_alloc_1(K_OTHER, caml_copy_int32((int32_t)event->type)));
    }

    window = caml_copy_int32((int32_t)event->windowID);
    CAMLreturn(caml_alloc_2(K_WINDOW, window, change));
}

/* Sdl3.Event.display_change constant constructor order. */
static value display_event_value(const SDL_DisplayEvent* event) {
    int change;
    switch (event->type) {
    case SDL_EVENT_DISPLAY_ADDED:
        change = 0;
        break;
    case SDL_EVENT_DISPLAY_REMOVED:
        change = 1;
        break;
    case SDL_EVENT_DISPLAY_MOVED:
        change = 2;
        break;
    case SDL_EVENT_DISPLAY_DESKTOP_MODE_CHANGED:
        change = 3;
        break;
    case SDL_EVENT_DISPLAY_CURRENT_MODE_CHANGED:
        change = 4;
        break;
    case SDL_EVENT_DISPLAY_CONTENT_SCALE_CHANGED:
        change = 5;
        break;
    default:
        return caml_alloc_1(K_OTHER, caml_copy_int32((int32_t)event->type));
    }
    return caml_alloc_2(K_DISPLAY, caml_copy_int32((int32_t)event->displayID), Val_int(change));
}

static value touch_event_value(const SDL_TouchFingerEvent* event, int change) {
    CAMLparam0();
    CAMLlocal5(window, device, finger, dx, dy);

    window =
        event->windowID ? caml_alloc_some(caml_copy_int32((int32_t)event->windowID)) : Val_none;
    device = caml_copy_int64((int64_t)event->touchID);
    finger = finger_value(event->fingerID, event->x, event->y, event->pressure);
    dx     = caml_copy_double(event->dx);
    dy     = caml_copy_double(event->dy);
    CAMLreturn(caml_alloc_6(K_TOUCH, window, device, finger, Val_int(change), dx, dy));
}

static value drop_event_value(const SDL_DropEvent* event) {
    CAMLparam0();
    CAMLlocal4(window, change, x, y);

    /* SDL owns the event data. Copy it before another poll can free it. */
    switch (event->type) {
    case SDL_EVENT_DROP_BEGIN:
        change = Val_int(0);
        break;
    case SDL_EVENT_DROP_COMPLETE:
        change = Val_int(1);
        break;
    case SDL_EVENT_DROP_FILE:
    case SDL_EVENT_DROP_TEXT:
        if (!event->data) CAMLreturn(caml_alloc_1(K_OTHER, caml_copy_int32((int32_t)event->type)));
        change =
            caml_alloc_1(event->type == SDL_EVENT_DROP_FILE ? 0 : 1, caml_copy_string(event->data));
        break;
    case SDL_EVENT_DROP_POSITION:
        x      = caml_copy_double(event->x);
        y      = caml_copy_double(event->y);
        change = caml_alloc_2(2, x, y);
        break;
    default:
        CAMLreturn(caml_alloc_1(K_OTHER, caml_copy_int32((int32_t)event->type)));
    }

    window =
        event->windowID ? caml_alloc_some(caml_copy_int32((int32_t)event->windowID)) : Val_none;
    CAMLreturn(caml_alloc_2(K_DROP, window, change));
}

static value event_kind_value(const SDL_Event* event) {
    if (event->type >= SDL_EVENT_WINDOW_FIRST && event->type <= SDL_EVENT_WINDOW_LAST)
        return window_event_value(&event->window);
    if (event->type >= SDL_EVENT_DISPLAY_FIRST && event->type <= SDL_EVENT_DISPLAY_LAST)
        return display_event_value(&event->display);

    CAMLparam0();
    CAMLlocal5(window, x, y, a, b);
    CAMLlocal1(c);

    switch (event->type) {
    case SDL_EVENT_QUIT:
        CAMLreturn(Val_int(0));

    case SDL_EVENT_KEY_DOWN:
    case SDL_EVENT_KEY_UP:
        window = caml_copy_int32((int32_t)event->key.windowID);
        a      = caml_copy_int32((int32_t)event->key.key);
        CAMLreturn(caml_alloc_6(K_KEY, window, Val_int(event->key.scancode), a,
                                Val_int(event->key.mod), Val_bool(event->key.down),
                                Val_bool(event->key.repeat)));

    case SDL_EVENT_TEXT_INPUT:
        a      = caml_copy_string(event->text.text ? event->text.text : "");
        window = caml_copy_int32((int32_t)event->text.windowID);
        CAMLreturn(caml_alloc_2(K_TEXT_INPUT, window, a));

    case SDL_EVENT_TEXT_EDITING:
        a      = caml_copy_string(event->edit.text ? event->edit.text : "");
        window = caml_copy_int32((int32_t)event->edit.windowID);
        CAMLreturn(caml_alloc_4(K_TEXT_EDITING, window, a, osdl_val_int(event->edit.start),
                                osdl_val_int(event->edit.length)));

    case SDL_EVENT_MOUSE_MOTION:
        window = caml_copy_int32((int32_t)event->motion.windowID);
        x      = caml_copy_double(event->motion.x);
        y      = caml_copy_double(event->motion.y);
        a      = caml_copy_double(event->motion.xrel);
        b      = caml_copy_double(event->motion.yrel);
        c      = caml_copy_int32((int32_t)event->motion.state);
        CAMLreturn(caml_alloc_6(K_MOUSE_MOTION, window, x, y, a, b, c));

    case SDL_EVENT_MOUSE_BUTTON_DOWN:
    case SDL_EVENT_MOUSE_BUTTON_UP:
        window = caml_copy_int32((int32_t)event->button.windowID);
        a      = mouse_button_value(event->button.button);
        x      = caml_copy_double(event->button.x);
        y      = caml_copy_double(event->button.y);
        CAMLreturn(caml_alloc_6(K_MOUSE_BUTTON, window, a, Val_bool(event->button.down),
                                Val_int(event->button.clicks), x, y));

    case SDL_EVENT_MOUSE_WHEEL:
        window = caml_copy_int32((int32_t)event->wheel.windowID);
        x      = caml_copy_double(event->wheel.x);
        y      = caml_copy_double(event->wheel.y);
        CAMLreturn(caml_alloc_4(K_MOUSE_WHEEL, window, x, y,
                                Val_bool(event->wheel.direction == SDL_MOUSEWHEEL_FLIPPED)));

    case SDL_EVENT_GAMEPAD_ADDED:
        CAMLreturn(caml_alloc_1(K_GAMEPAD_ADDED, caml_copy_int32((int32_t)event->gdevice.which)));
    case SDL_EVENT_GAMEPAD_REMOVED:
        CAMLreturn(caml_alloc_1(K_GAMEPAD_REMOVED, caml_copy_int32((int32_t)event->gdevice.which)));
    case SDL_EVENT_GAMEPAD_REMAPPED:
        CAMLreturn(
            caml_alloc_1(K_GAMEPAD_REMAPPED, caml_copy_int32((int32_t)event->gdevice.which)));

    case SDL_EVENT_GAMEPAD_AXIS_MOTION:
        for (size_t i = 0; i < SDL_arraysize(gamepad_axes); ++i) {
            if (gamepad_axes[i] == event->gaxis.axis) {
                a = caml_copy_int32((int32_t)event->gaxis.which);
                CAMLreturn(
                    caml_alloc_3(K_GAMEPAD_AXIS, a, Val_int(i), Val_int(event->gaxis.value)));
            }
        }
        break;

    case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
    case SDL_EVENT_GAMEPAD_BUTTON_UP:
        for (size_t i = 0; i < SDL_arraysize(gamepad_buttons); ++i) {
            if (gamepad_buttons[i] == event->gbutton.button) {
                a = caml_copy_int32((int32_t)event->gbutton.which);
                CAMLreturn(
                    caml_alloc_3(K_GAMEPAD_BUTTON, a, Val_int(i), Val_bool(event->gbutton.down)));
            }
        }
        break;

    /* Sdl3.Event.touch_change constant constructor order. */
    case SDL_EVENT_FINGER_DOWN:
        CAMLreturn(touch_event_value(&event->tfinger, 0));
    case SDL_EVENT_FINGER_UP:
        CAMLreturn(touch_event_value(&event->tfinger, 1));
    case SDL_EVENT_FINGER_MOTION:
        CAMLreturn(touch_event_value(&event->tfinger, 2));
    case SDL_EVENT_FINGER_CANCELED:
        CAMLreturn(touch_event_value(&event->tfinger, 3));

    case SDL_EVENT_DROP_BEGIN:
    case SDL_EVENT_DROP_COMPLETE:
    case SDL_EVENT_DROP_FILE:
    case SDL_EVENT_DROP_TEXT:
    case SDL_EVENT_DROP_POSITION:
        CAMLreturn(drop_event_value(&event->drop));

    default:
        break;
    }
    CAMLreturn(caml_alloc_1(K_OTHER, caml_copy_int32((int32_t)event->type)));
}

CAMLprim value osdl_event_poll(value context) {
    SDL_Event event;
    osdl_live(context);
    if (!SDL_PollEvent(&event)) return Val_none;

    CAMLparam0();
    CAMLlocal2(kind, time);

    kind = event_kind_value(&event);
    time = caml_copy_int64((int64_t)event.common.timestamp);
    CAMLreturn(caml_alloc_some(caml_alloc_2(0, time, kind)));
}

CAMLprim value osdl_event_convert_coordinates(value renderer, value window, value touch, value x,
                                              value y, value dx, value dy) {
    SDL_Renderer* r = osdl_live(renderer);
    if (Is_long(window)) return Val_none;
    SDL_Window*  owned = SDL_GetRenderWindow(r);
    SDL_WindowID id    = (SDL_WindowID)Int32_val(Some_val(window));
    if (!owned || !id || SDL_GetWindowID(owned) != id) return Val_none;

    /* Only SDL's coordinate fields go into this temporary event. Keep the
     * original event, including its IDs and other data, in OCaml. */
    SDL_FPoint position = {osdl_float(Double_val(x)), osdl_float(Double_val(y))};
    SDL_FPoint movement = {osdl_float(Double_val(dx)), osdl_float(Double_val(dy))};
    SDL_Event  event    = {0};
    bool       finger   = Bool_val(touch);
    if (finger) {
        event.tfinger = (SDL_TouchFingerEvent){.type     = SDL_EVENT_FINGER_MOTION,
                                               .windowID = id,
                                               .x        = position.x,
                                               .y        = position.y,
                                               .dx       = movement.x,
                                               .dy       = movement.y};
    } else {
        event.motion = (SDL_MouseMotionEvent){.type     = SDL_EVENT_MOUSE_MOTION,
                                              .windowID = id,
                                              .x        = position.x,
                                              .y        = position.y,
                                              .xrel     = movement.x,
                                              .yrel     = movement.y};
    }

    osdl_check(SDL_ConvertEventToRenderCoordinates(r, &event),
               "SDL_ConvertEventToRenderCoordinates");
    if (finger) {
        position = (SDL_FPoint){event.tfinger.x, event.tfinger.y};
        movement = (SDL_FPoint){event.tfinger.dx, event.tfinger.dy};
    } else {
        position = (SDL_FPoint){event.motion.x, event.motion.y};
        movement = (SDL_FPoint){event.motion.xrel, event.motion.yrel};
    }
    if (!osdl_fits_float(position.x) || !osdl_fits_float(position.y) ||
        !osdl_fits_float(movement.x) || !osdl_fits_float(movement.y))
        caml_invalid_argument("The converted coordinates must be finite C floats");

    CAMLparam0();
    CAMLlocal1(result);

    /* Sdl3.Event.coordinates contains four floats in this order. */
    result = caml_alloc_small(4 * Double_wosize, Double_array_tag);
    Store_double_flat_field(result, 0, position.x);
    Store_double_flat_field(result, 1, position.y);
    Store_double_flat_field(result, 2, movement.x);
    Store_double_flat_field(result, 3, movement.y);
    CAMLreturn(caml_alloc_some(result));
}

CAMLprim value osdl_event_convert_coordinates_byte(value* argv, int argc) {
    (void)argc;
    return osdl_event_convert_coordinates(argv[0], argv[1], argv[2], argv[3], argv[4], argv[5],
                                          argv[6]);
}
