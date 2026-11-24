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
    K_OTHER,
};

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
    case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
        change = caml_alloc_2(event->type == SDL_EVENT_WINDOW_RESIZED ? 0 : 1,
                              osdl_val_int(event->data1), osdl_val_int(event->data2));
        break;
    default:
        CAMLreturn(caml_alloc_1(K_OTHER, caml_copy_int32((int32_t)event->type)));
    }

    window = caml_copy_int32((int32_t)event->windowID);
    CAMLreturn(caml_alloc_2(K_WINDOW, window, change));
}

static value event_kind_value(const SDL_Event* event) {
    CAMLparam0();
    CAMLlocal5(window, x, y, a, b);
    CAMLlocal1(c);

    switch (event->type) {
    case SDL_EVENT_QUIT:
        CAMLreturn(Val_int(0));

    case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
    case SDL_EVENT_WINDOW_FOCUS_GAINED:
    case SDL_EVENT_WINDOW_FOCUS_LOST:
    case SDL_EVENT_WINDOW_RESIZED:
    case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
        CAMLreturn(window_event_value(&event->window));

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

    default:
        CAMLreturn(caml_alloc_1(K_OTHER, caml_copy_int32((int32_t)event->type)));
    }
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
