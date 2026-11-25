#include <SDL3/SDL.h>

#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/mlvalues.h>

static void push(SDL_Event event) {
    if (!SDL_PushEvent(&event)) caml_failwith(SDL_GetError());
}

/* The test controls the event queue on the dummy video driver. */
CAMLprim value test_push_events(value window) {
    SDL_WindowID id = (Uint32)Int32_val(window);
    SDL_PumpEvents();
    SDL_FlushEvents(SDL_EVENT_FIRST, SDL_EVENT_LAST);

    push((SDL_Event){
        .window = {.type      = SDL_EVENT_WINDOW_RESIZED,
                   .timestamp = 1234,
                   .windowID  = id,
                   .data1     = 320,
                   .data2     = 240}
    });
    push((SDL_Event){
        .window = {.type     = SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED,
                   .windowID = id,
                   .data1    = 640,
                   .data2    = 480}
    });
    push((SDL_Event){
        .window = {.type = SDL_EVENT_WINDOW_CLOSE_REQUESTED, .windowID = id}
    });

    push((SDL_Event){
        .key = {.type     = SDL_EVENT_KEY_DOWN,
                .windowID = id,
                .scancode = SDL_SCANCODE_ESCAPE,
                .key      = SDLK_ESCAPE,
                .mod      = SDL_KMOD_LSHIFT,
                .down     = true,
                .repeat   = true}
    });
    push((SDL_Event){
        .text = {.type = SDL_EVENT_TEXT_INPUT, .windowID = id, .text = "\xc3\xa9"}
    });
    push((SDL_Event){
        .edit = {.type     = SDL_EVENT_TEXT_EDITING,
                 .windowID = id,
                 .text     = "test",
                 .start    = 1,
                 .length   = 2}
    });

    push((SDL_Event){
        .motion = {.type     = SDL_EVENT_MOUSE_MOTION,
                   .windowID = id,
                   .state    = SDL_BUTTON_LMASK,
                   .x        = 2.5f,
                   .y        = 3.5f,
                   .xrel     = -1.5f,
                   .yrel     = 0.5f}
    });
    push((SDL_Event){
        .button = {.type     = SDL_EVENT_MOUSE_BUTTON_DOWN,
                   .windowID = id,
                   .button   = SDL_BUTTON_X1,
                   .down     = true,
                   .clicks   = 2,
                   .x        = 1.25f,
                   .y        = 2.75f}
    });
    push((SDL_Event){
        .wheel = {.type      = SDL_EVENT_MOUSE_WHEEL,
                  .windowID  = id,
                  .x         = 0.5f,
                  .y         = -1.0f,
                  .direction = SDL_MOUSEWHEEL_FLIPPED}
    });

    push((SDL_Event){
        .gdevice = {.type = SDL_EVENT_GAMEPAD_ADDED, .which = 123}
    });
    push((SDL_Event){
        .gdevice = {.type = SDL_EVENT_GAMEPAD_REMOVED, .which = 123}
    });

    push((SDL_Event){.type = SDL_EVENT_USER});
    push((SDL_Event){.type = SDL_EVENT_QUIT});

    return Val_unit;
}

CAMLprim value test_push_device_events(value window) {
    SDL_WindowID  id      = (SDL_WindowID)Int32_val(window);
    SDL_DisplayID display = SDL_GetPrimaryDisplay();
    SDL_PumpEvents();
    SDL_FlushEvents(SDL_EVENT_FIRST, SDL_EVENT_LAST);

    push((SDL_Event){
        .window = {.type = SDL_EVENT_WINDOW_MOVED, .windowID = id, .data1 = -17, .data2 = 23}
    });
    push((SDL_Event){
        .window = {
                   .type = SDL_EVENT_WINDOW_DISPLAY_CHANGED, .windowID = id, .data1 = (Sint32)display}
    });

    const SDL_EventType window_types[] = {
        SDL_EVENT_WINDOW_SHOWN,
        SDL_EVENT_WINDOW_HIDDEN,
        SDL_EVENT_WINDOW_MINIMIZED,
        SDL_EVENT_WINDOW_MAXIMIZED,
        SDL_EVENT_WINDOW_RESTORED,
        SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED,
        SDL_EVENT_WINDOW_ENTER_FULLSCREEN,
        SDL_EVENT_WINDOW_LEAVE_FULLSCREEN,
    };
    for (size_t i = 0; i < SDL_arraysize(window_types); ++i)
        push((SDL_Event){
            .window = {.type = window_types[i], .windowID = id}
        });

    const SDL_EventType display_types[] = {
        SDL_EVENT_DISPLAY_ADDED,
        SDL_EVENT_DISPLAY_REMOVED,
        SDL_EVENT_DISPLAY_MOVED,
        SDL_EVENT_DISPLAY_DESKTOP_MODE_CHANGED,
        SDL_EVENT_DISPLAY_CURRENT_MODE_CHANGED,
        SDL_EVENT_DISPLAY_CONTENT_SCALE_CHANGED,
    };
    for (size_t i = 0; i < SDL_arraysize(display_types); ++i)
        push((SDL_Event){
            .display = {.type = display_types[i], .displayID = display}
        });

    push((SDL_Event){
        .display = {.type = SDL_EVENT_DISPLAY_REMOVED, .displayID = UINT32_C(0xffffffff)}
    });

    const SDL_EventType touch_types[] = {
        SDL_EVENT_FINGER_DOWN,
        SDL_EVENT_FINGER_MOTION,
        SDL_EVENT_FINGER_UP,
        SDL_EVENT_FINGER_CANCELED,
    };
    for (size_t i = 0; i < SDL_arraysize(touch_types); ++i) {
        bool canceled = touch_types[i] == SDL_EVENT_FINGER_CANCELED;
        push((SDL_Event){
            .tfinger = {.type     = touch_types[i],
                        .windowID = canceled ? 0 : id,
                        .touchID  = canceled ? UINT64_C(0xbeef0000dead9876) : SDL_MOUSE_TOUCHID,
                        .fingerID = UINT64_C(0xf123456789abcdef),
                        .x        = 0.25f,
                        .y        = 0.75f,
                        .dx       = -0.125f,
                        .dy       = 0.5f,
                        .pressure = 0.625f}
        });
    }

    push((SDL_Event){
        .gdevice = {.type = SDL_EVENT_GAMEPAD_REMAPPED, .which = 123}
    });
    push((SDL_Event){
        .gaxis = {.type = SDL_EVENT_GAMEPAD_AXIS_MOTION, .which = 123, .axis = 255}
    });
    push((SDL_Event){
        .gbutton = {.type = SDL_EVENT_GAMEPAD_BUTTON_DOWN, .which = 123, .button = 255}
    });

    return Val_unit;
}

CAMLprim value test_attach_gamepad(value unit) {
    (void)unit;

    SDL_VirtualJoystickDesc desc;
    SDL_INIT_INTERFACE(&desc);
    desc.type        = SDL_JOYSTICK_TYPE_GAMEPAD;
    desc.naxes       = 1;
    desc.nbuttons    = 2;
    desc.axis_mask   = 1u << SDL_GAMEPAD_AXIS_LEFTX;
    desc.button_mask = (1u << SDL_GAMEPAD_BUTTON_SOUTH) | (1u << SDL_GAMEPAD_BUTTON_LEFT_PADDLE2);
    desc.name        = "OCaml SDL test gamepad";

    SDL_JoystickID id = SDL_AttachVirtualJoystick(&desc);
    if (!id) caml_failwith(SDL_GetError());
    return caml_copy_int32((int32_t)id);
}

CAMLprim value test_detach_gamepad(value id) {
    if (!SDL_DetachVirtualJoystick((SDL_JoystickID)Int32_val(id))) caml_failwith(SDL_GetError());
    return Val_unit;
}

CAMLprim value test_set_gamepad_state(value id, value axis, value pressed) {
    SDL_Joystick* joystick = SDL_GetJoystickFromID((SDL_JoystickID)Int32_val(id));
    if (!joystick || !SDL_SetJoystickVirtualAxis(joystick, 0, (Sint16)Int_val(axis)) ||
        !SDL_SetJoystickVirtualButton(joystick, 1, Bool_val(pressed)))
        caml_failwith(SDL_GetError());
    SDL_UpdateJoysticks();
    return Val_unit;
}
