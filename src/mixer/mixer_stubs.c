#include "sdl3_stubs.h"

#include <SDL3_mixer/SDL_mixer.h>

/* SDL_mixer context. */

static char mixer_initialized;

CAMLprim value osdl_mixer_version(value unit) {
    (void)unit;
    return osdl_version_value(MIX_Version());
}

CAMLprim value osdl_mixer_init(value sdl) {
    CAMLparam1(sdl);
    CAMLlocal1(context);

    context = osdl_new_handle(sdl);
    osdl_live(sdl);

    osdl_check(MIX_Init(), "MIX_Init");
    CAMLreturn(osdl_publish(context, &mixer_initialized, "MIX_Init"));
}

CAMLprim value osdl_mixer_quit(value context) {
    if (osdl_take(context)) MIX_Quit();
    return Val_unit;
}

/* Mixers. */

CAMLprim value osdl_mixer_create_device(value spec, value context) {
    CAMLparam2(spec, context);
    CAMLlocal1(handle);

    handle = osdl_new_handle(context);
    osdl_live(context);

    SDL_AudioSpec        format;
    const SDL_AudioSpec* requested = NULL;
    if (Is_block(spec)) {
        format    = osdl_audio_spec(Some_val(spec));
        requested = &format;
    }

    MIX_Mixer* mixer = MIX_CreateMixerDevice(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, requested);
    CAMLreturn(osdl_publish(handle, mixer, "MIX_CreateMixerDevice"));
}

CAMLprim value osdl_mixer_create(value context, value spec) {
    CAMLparam2(context, spec);
    CAMLlocal1(handle);

    handle = osdl_new_handle(context);
    osdl_live(context);

    SDL_AudioSpec format = osdl_audio_spec(spec);
    CAMLreturn(osdl_publish(handle, MIX_CreateMixer(&format), "MIX_CreateMixer"));
}

OSDL_DESTROY(osdl_mixer_destroy, MIX_Mixer, MIX_DestroyMixer)

CAMLprim value osdl_mixer_generate(value mixer, value buffer) {
    MIX_Mixer* m    = osdl_live(mixer);
    int        size = osdl_audio_buffer_length(buffer);
    if (!size) return Val_int(0);

    int mixed = MIX_Generate(m, Caml_ba_data_val(buffer), size);
    if (mixed < 0) osdl_fail("MIX_Generate");
    return osdl_val_int(mixed);
}

static float mixer_gain(value gain) {
    double g = Double_val(gain);
    if (g < 0) caml_invalid_argument("SDL_mixer gain must not be negative");
    return osdl_float(g);
}

CAMLprim value osdl_mixer_set_gain(value mixer, value gain) {
    osdl_check(MIX_SetMixerGain(osdl_live(mixer), mixer_gain(gain)), "MIX_SetMixerGain");
    return Val_unit;
}

/* Loaded audio. */

CAMLprim value osdl_mixer_audio_load(value predecode, value context, value path) {
    CAMLparam3(predecode, context, path);
    CAMLlocal1(handle);

    handle = osdl_new_handle(context);
    osdl_live(context);

    bool       decode = Is_block(predecode) && Bool_val(Some_val(predecode));
    MIX_Audio* audio  = MIX_LoadAudio(NULL, osdl_cstring(path), decode);
    CAMLreturn(osdl_publish(handle, audio, "MIX_LoadAudio"));
}

CAMLprim value osdl_mixer_audio_load_io(value predecode, value context, value stream) {
    CAMLparam3(predecode, context, stream);
    CAMLlocal1(handle);

    osdl_live(context);
    SDL_IOStream* io     = osdl_unborrowed_io(stream);
    bool          decode = Is_block(predecode) && Bool_val(Some_val(predecode));
    handle               = osdl_new_handle(context);

    MIX_Audio* audio = MIX_LoadAudio_IO(NULL, io, decode, false);
    CAMLreturn(osdl_publish(handle, audio, "MIX_LoadAudio_IO"));
}

OSDL_DESTROY(osdl_mixer_audio_destroy, MIX_Audio, MIX_DestroyAudio)

CAMLprim value osdl_mixer_audio_duration(value audio) {
    Sint64 frames = MIX_GetAudioDuration(osdl_live(audio));
    if (frames == MIX_DURATION_INFINITE) return Val_int(1);
    if (frames < 0) return Val_int(0);
    return caml_alloc_1(0, caml_copy_int64(frames));
}

/* Tracks. */

CAMLprim value osdl_mixer_track_create(value mixer) {
    CAMLparam1(mixer);
    CAMLlocal1(handle);

    handle = osdl_new_handle(mixer);
    CAMLreturn(osdl_publish(handle, MIX_CreateTrack(osdl_live(mixer)), "MIX_CreateTrack"));
}

OSDL_DESTROY(osdl_mixer_track_destroy, MIX_Track, MIX_DestroyTrack)

CAMLprim value osdl_mixer_track_set_audio(value track, value audio) {
    MIX_Audio* a = Is_long(audio) ? NULL : osdl_live(Some_val(audio));
    osdl_check(MIX_SetTrackAudio(osdl_live(track), a), "MIX_SetTrackAudio");
    return Val_unit;
}

CAMLprim value osdl_mixer_track_play(value loops, value track) {
    MIX_Track* t     = osdl_live(track);
    int        count = Is_long(loops) ? 0 : osdl_int(Some_val(loops));
    if (count < -1) caml_invalid_argument("SDL_mixer loop count must be at least -1");

    if (count == 0) {
        osdl_check(MIX_PlayTrack(t, 0), "MIX_PlayTrack");
        return Val_unit;
    }

    SDL_PropertiesID props = SDL_CreateProperties();
    if (!props) osdl_fail("SDL_CreateProperties");

    const char* failure = NULL;
    if (!SDL_SetNumberProperty(props, MIX_PROP_PLAY_LOOPS_NUMBER, count))
        failure = "SDL_SetNumberProperty";
    else if (!MIX_PlayTrack(t, props))
        failure = "MIX_PlayTrack";

    if (failure) {
        char message[1024];
        osdl_error_message(message, sizeof(message), failure);
        SDL_DestroyProperties(props);
        osdl_raise_error(message);
    }
    SDL_DestroyProperties(props);
    return Val_unit;
}

CAMLprim value osdl_mixer_track_stop(value frames, value track) {
    Sint64 fade = Is_long(frames) ? 0 : Int64_val(Some_val(frames));
    if (fade < 0) caml_invalid_argument("SDL_mixer fade length must not be negative");
    osdl_check(MIX_StopTrack(osdl_live(track), fade), "MIX_StopTrack");
    return Val_unit;
}

OSDL_ACTION(osdl_mixer_track_pause, MIX_PauseTrack)
OSDL_ACTION(osdl_mixer_track_resume, MIX_ResumeTrack)

CAMLprim value osdl_mixer_track_playing(value track) {
    return Val_bool(MIX_TrackPlaying(osdl_live(track)));
}

CAMLprim value osdl_mixer_track_paused(value track) {
    return Val_bool(MIX_TrackPaused(osdl_live(track)));
}

CAMLprim value osdl_mixer_track_set_gain(value track, value gain) {
    osdl_check(MIX_SetTrackGain(osdl_live(track), mixer_gain(gain)), "MIX_SetTrackGain");
    return Val_unit;
}
