#include <SDL3/SDL.h>

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
