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

CAMLprim value osdl_mixer_create_device(value device, value spec, value context) {
    CAMLparam3(device, spec, context);
    CAMLlocal1(handle);

    handle = osdl_new_handle(context);
    osdl_live(context);

    SDL_AudioSpec        format;
    const SDL_AudioSpec* requested = NULL;
    if (Is_block(spec)) {
        format    = osdl_audio_spec(Some_val(spec));
        requested = &format;
    }

    SDL_AudioDeviceID id = osdl_audio_device_or_default(device, SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK);
    MIX_Mixer*        mixer = MIX_CreateMixerDevice(id, requested);
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

CAMLprim value osdl_mixer_audio_title(value audio) {
    CAMLparam1(audio);
    CAMLlocal1(title);

    SDL_PropertiesID properties = MIX_GetAudioProperties(osdl_live(audio));
    if (!properties) osdl_fail("MIX_GetAudioProperties");

    const char* text = SDL_GetStringProperty(properties, MIX_PROP_METADATA_TITLE_STRING, NULL);
    if (!text || !*text) CAMLreturn(Val_none);
    title = caml_copy_string(text);
    CAMLreturn(caml_alloc_some(title));
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

static int mixer_loop_count(value loops) {
    int count = osdl_int(loops);
    if (count < -1) caml_invalid_argument("SDL_mixer loop count must be at least -1");
    return count;
}

static Sint64 mixer_frame_position(MIX_Track* track, value frame) {
    Sint64 position = Int64_val(frame);
    if (position < 0) caml_invalid_argument("SDL_mixer position must not be negative");
    if (position > 0) {
        MIX_Audio* audio = MIX_GetTrackAudio(track);
        if (audio) {
            Sint64 duration = MIX_GetAudioDuration(audio);
            if (duration >= 0 && position > duration)
                caml_invalid_argument("SDL_mixer position is past the end of the audio");
        }
    }
    return position;
}

static Sint64 mixer_fade_length(value frames) {
    Sint64 fade = Int64_val(frames);
    /* SDL_mixer uses int counters when applying the fade. */
    if (fade < 0 || fade > INT_MAX)
        caml_invalid_argument("SDL_mixer fade length must be between 0 and 2147483647 frames");
    return fade;
}

CAMLprim value osdl_mixer_track_play(value loops, value start_frame, value fade_in_frames,
                                     value track) {
    MIX_Track* t        = osdl_live(track);
    int        count    = Is_long(loops) ? 0 : mixer_loop_count(Some_val(loops));
    Sint64     position = Is_long(start_frame) ? 0 : mixer_frame_position(t, Some_val(start_frame));
    Sint64     fade     = Is_long(fade_in_frames) ? 0 : mixer_fade_length(Some_val(fade_in_frames));

    if (count == 0 && position == 0 && fade == 0) {
        osdl_check(MIX_PlayTrack(t, 0), "MIX_PlayTrack");
        return Val_unit;
    }

    SDL_PropertiesID props = SDL_CreateProperties();
    if (!props) osdl_fail("SDL_CreateProperties");

    const char* failure = NULL;
    if ((count != 0 && !SDL_SetNumberProperty(props, MIX_PROP_PLAY_LOOPS_NUMBER, count)) ||
        (position != 0 &&
         !SDL_SetNumberProperty(props, MIX_PROP_PLAY_START_FRAME_NUMBER, position)) ||
        (fade != 0 && !SDL_SetNumberProperty(props, MIX_PROP_PLAY_FADE_IN_FRAMES_NUMBER, fade)))
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
    MIX_Track* t    = osdl_live(track);
    Sint64     fade = Is_long(frames) ? 0 : mixer_fade_length(Some_val(frames));

    osdl_check(MIX_StopTrack(t, fade), "MIX_StopTrack");
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

CAMLprim value osdl_mixer_track_position(value track) {
    Sint64 position = MIX_GetTrackPlaybackPosition(osdl_live(track));
    if (position < 0) osdl_fail("MIX_GetTrackPlaybackPosition");
    return caml_copy_int64(position);
}

CAMLprim value osdl_mixer_track_seek(value track, value frame) {
    MIX_Track* t        = osdl_live(track);
    Sint64     position = mixer_frame_position(t, frame);

    osdl_check(MIX_SetTrackPlaybackPosition(t, position), "MIX_SetTrackPlaybackPosition");
    return Val_unit;
}

CAMLprim value osdl_mixer_track_loops(value track) {
    return osdl_val_int(MIX_GetTrackLoops(osdl_live(track)));
}

CAMLprim value osdl_mixer_track_set_loops(value track, value loops) {
    MIX_Track* t     = osdl_live(track);
    int        count = mixer_loop_count(loops);

    osdl_check(MIX_SetTrackLoops(t, count), "MIX_SetTrackLoops");
    return Val_unit;
}

CAMLprim value osdl_mixer_track_fade_frames(value track) {
    return caml_copy_int64(MIX_GetTrackFadeFrames(osdl_live(track)));
}

CAMLprim value osdl_mixer_track_frequency_ratio(value track) {
    float ratio = MIX_GetTrackFrequencyRatio(osdl_live(track));
    if (ratio <= 0.0f) osdl_fail("MIX_GetTrackFrequencyRatio");
    return caml_copy_double(ratio);
}

CAMLprim value osdl_mixer_track_set_frequency_ratio(value track, value ratio) {
    MIX_Track* t = osdl_live(track);
    float      r = osdl_float(Double_val(ratio));
    if (r < 0.01f || r > 100.0f)
        caml_invalid_argument("SDL_mixer frequency ratio must be between 0.01 and 100");

    osdl_check(MIX_SetTrackFrequencyRatio(t, r), "MIX_SetTrackFrequencyRatio");
    return Val_unit;
}

CAMLprim value osdl_mixer_track_set_gain(value track, value gain) {
    osdl_check(MIX_SetTrackGain(osdl_live(track), mixer_gain(gain)), "MIX_SetTrackGain");
    return Val_unit;
}
