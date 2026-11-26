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

/* A mixer's attachment is its fixed channel count or a device marker. */
enum { OSDL_MIXER_DEVICE = -1, OSDL_MIXER_DEVICE_WITH_SPEC = -2 };

CAMLprim value osdl_mixer_create_device(value device, value spec, value context) {
    CAMLparam3(device, spec, context);
    CAMLlocal1(handle);

    int output = Is_long(spec) ? OSDL_MIXER_DEVICE : OSDL_MIXER_DEVICE_WITH_SPEC;
    handle     = osdl_new_attached_handle(context, Val_int(output));
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

    SDL_AudioSpec format = osdl_audio_spec(spec);
    handle               = osdl_new_attached_handle(context, Val_int(format.channels));
    osdl_live(context);

    CAMLreturn(osdl_publish(handle, MIX_CreateMixer(&format), "MIX_CreateMixer"));
}

OSDL_DESTROY(osdl_mixer_destroy, MIX_Mixer, MIX_DestroyMixer)

CAMLprim value osdl_mixer_generate(value mixer, value buffer) {
    MIX_Mixer* m    = osdl_live(mixer);
    int        size = osdl_audio_buffer_length(buffer);
    if (!size) return Val_int(0);

    /* With groups, SDL_mixer sizes three float buffers with signed int math.
     * An offline mix has the same frame rate and channel count in all buffers. */
    const int scratch_bytes = 3 * (int)sizeof(float);
    if (size > INT_MAX / scratch_bytes) {
        SDL_AudioSpec spec;
        osdl_check(MIX_GetMixerFormat(m, &spec), "MIX_GetMixerFormat");
        if ((Sint64)size * scratch_bytes > (Sint64)INT_MAX * SDL_AUDIO_BYTESIZE(spec.format))
            caml_invalid_argument("The mix buffer is too large. Mix audio in smaller blocks");
    }

    int mixed = MIX_Generate(m, Caml_ba_data_val(buffer), size);
    if (mixed < 0) osdl_fail("MIX_Generate");
    return osdl_val_int(mixed);
}

static float mixer_gain(double g) {
    if (g < 0) caml_invalid_argument("SDL_mixer gain must not be negative");
    return osdl_float(g);
}

CAMLprim value osdl_mixer_set_gain(value mixer, value gain) {
    osdl_check(MIX_SetMixerGain(osdl_live(mixer), mixer_gain(Double_val(gain))),
               "MIX_SetMixerGain");
    return Val_unit;
}

/* Mixer-wide tag controls. */

static const char* mixer_tag(value tag) {
    const char* name = osdl_cstring(tag);
    if (!*name) caml_invalid_argument("SDL_mixer tags must not be empty");
    return name;
}

CAMLprim value osdl_mixer_set_tag_gain(value mixer, value tag, value gain) {
    MIX_Mixer*  m    = osdl_live(mixer);
    const char* name = mixer_tag(tag);
    float       g    = mixer_gain(Double_val(gain));

    osdl_check(MIX_SetTagGain(m, name, g), "MIX_SetTagGain");
    return Val_unit;
}

CAMLprim value osdl_mixer_stop_tag(value fade_ms, value mixer, value tag) {
    MIX_Mixer*  m    = osdl_live(mixer);
    const char* name = mixer_tag(tag);
    Sint64      fade = Is_long(fade_ms) ? 0 : Int64_val(Some_val(fade_ms));
    if (fade < 0 || fade > (Sint64)INT_MAX * 1000)
        caml_invalid_argument("SDL_mixer tag fade length is out of range");

    /* Keep input rates stable during validation and start the fades together.
     * Up to one second fits the mixer's int counters at any C int sample rate. */
    MIX_LockMixer(m);
    if (fade > 1000) {
        int         count;
        MIX_Track** tracks = MIX_GetTaggedTracks(m, name, &count);
        if (!tracks) {
            MIX_UnlockMixer(m);
            osdl_fail("MIX_GetTaggedTracks");
        }
        bool fits = true;
        for (int i = 0; fits && i < count; ++i)
            fits = MIX_TrackMSToFrames(tracks[i], fade) <= INT_MAX;
        SDL_free(tracks);
        if (!fits) {
            MIX_UnlockMixer(m);
            caml_invalid_argument("SDL_mixer tag fade exceeds 2147483647 input frames");
        }
    }
    bool ok = MIX_StopTag(m, name, fade);
    MIX_UnlockMixer(m);

    osdl_check(ok, "MIX_StopTag");
    return Val_unit;
}

CAMLprim value osdl_mixer_pause_tag(value mixer, value tag) {
    MIX_Mixer*  m    = osdl_live(mixer);
    const char* name = mixer_tag(tag);

    osdl_check(MIX_PauseTag(m, name), "MIX_PauseTag");
    return Val_unit;
}

CAMLprim value osdl_mixer_resume_tag(value mixer, value tag) {
    MIX_Mixer*  m    = osdl_live(mixer);
    const char* name = mixer_tag(tag);

    osdl_check(MIX_ResumeTag(m, name), "MIX_ResumeTag");
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

/* Mixing groups. */

CAMLprim value osdl_mixer_group_create(value mixer) {
    CAMLparam1(mixer);
    CAMLlocal1(handle);

    handle       = osdl_new_handle(mixer);
    MIX_Mixer* m = osdl_live(mixer);
    /* Earlier releases can corrupt a group's list when moving a middle track. */
    if (MIX_Version() < SDL_VERSIONNUM(3, 2, 4))
        osdl_raise_error("MIX_CreateGroup: Use SDL_mixer 3.2.4 or later for mixing groups");

    CAMLreturn(osdl_publish(handle, MIX_CreateGroup(m), "MIX_CreateGroup"));
}

OSDL_DESTROY(osdl_mixer_group_destroy, MIX_Group, MIX_DestroyGroup)

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
    osdl_check(MIX_SetTrackGain(osdl_live(track), mixer_gain(Double_val(gain))),
               "MIX_SetTrackGain");
    return Val_unit;
}

/* Track spatialization. */

CAMLprim value osdl_mixer_track_set_stereo(value track, value gains) {
    MIX_Track* t     = osdl_live(track);
    value      mixer = osdl_parent(track);
    MIX_Mixer* m     = osdl_live(mixer);

    MIX_StereoGains        stereo;
    const MIX_StereoGains* requested = NULL;
    if (Is_block(gains)) {
        value args = Some_val(gains);
        stereo     = (MIX_StereoGains){.left  = mixer_gain(Double_flat_field(args, 0)),
                                       .right = mixer_gain(Double_flat_field(args, 1))};
        requested  = &stereo;

        /* SDL_mixer writes past mono mix buffers in forced-stereo mode. A
         * device mixer can switch to mono after this call, so require a fixed
         * output format instead. */
        int channels = Int_val(osdl_attachment(mixer));
        if (channels < 0) caml_invalid_argument("Use a memory mixer for stereo panning");
        if (channels < 2)
            caml_invalid_argument("Stereo panning needs at least two output channels");
    }

    /* Changing the mode can change the size of each track frame. Do not change
     * it between the mixer's size calculation and its read of the track. */
    MIX_LockMixer(m);
    bool ok = MIX_SetTrackStereo(t, requested);
    MIX_UnlockMixer(m);

    osdl_check(ok, "MIX_SetTrackStereo");
    return Val_unit;
}

/* Called with the mixer locked. */
static const char* mixer_set_position(MIX_Track* track, const MIX_Point3D* position) {
    if (!MIX_SetTrack3DPosition(track, position)) return "MIX_SetTrack3DPosition";
    if (position && position->y == position->z) {
        MIX_Point3D actual;
        if (!MIX_GetTrack3DPosition(track, &actual)) return "MIX_GetTrack3DPosition";
        if (actual.y != position->y) {
            /* SDL_mixer 3.2.0 through 3.2.4 can skip a Y-only change when the
             * new Y equals Z. Change X briefly without mixing at that point. */
            MIX_Point3D step = *position;
            step.x           = step.x == 0 ? 1.0f : 0.0f;
            if (!MIX_SetTrack3DPosition(track, &step) || !MIX_SetTrack3DPosition(track, position))
                return "MIX_SetTrack3DPosition";
        }
    }
    return NULL;
}

CAMLprim value osdl_mixer_track_set_3d_position(value track, value position) {
    MIX_Track* t     = osdl_live(track);
    value      mixer = osdl_parent(track);
    MIX_Mixer* m     = osdl_live(mixer);

    MIX_Point3D        point;
    const MIX_Point3D* requested = NULL;
    if (Is_block(position)) {
        /* SDL_mixer uses the actual device channels to select speakers, but
         * can allocate the mix buffer using the requested channel count. */
        if (Int_val(osdl_attachment(mixer)) == OSDL_MIXER_DEVICE_WITH_SPEC)
            caml_invalid_argument("Omit the device format when using SDL_mixer 3D positions");

        value  args = Some_val(position);
        double x = Double_flat_field(args, 0), y = Double_flat_field(args, 1),
               z = Double_flat_field(args, 2);
        point    = (MIX_Point3D){.x = osdl_float(x), .y = osdl_float(y), .z = osdl_float(z)};
        /* SDL_mixer squares and sums the coordinates in float. Leave room for rounding. */
        if (x * x + y * y + z * z > (double)FLT_MAX / 2)
            caml_invalid_argument("SDL_mixer 3D position is too far from the listener");
        /* In surround sound, SDL_mixer can round a point just behind due right
         * to a full turn and read past its speaker table. Use due right. */
        if (point.x > 0 && point.z > 0 && point.z <= point.x * (8.0f * FLT_EPSILON)) point.z = 0.0f;
        requested = &point;
    }

    MIX_LockMixer(m);
    const char* failure = mixer_set_position(t, requested);
    MIX_UnlockMixer(m);

    if (failure) osdl_fail(failure);
    return Val_unit;
}

/* Track tags and group assignment. */

CAMLprim value osdl_mixer_track_tag(value track, value tag) {
    MIX_Track*  t    = osdl_live(track);
    const char* name = mixer_tag(tag);

    osdl_check(MIX_TagTrack(t, name), "MIX_TagTrack");
    return Val_unit;
}

CAMLprim value osdl_mixer_track_untag(value track, value tag) {
    MIX_Track*  t    = osdl_live(track);
    const char* name = mixer_tag(tag);

    MIX_UntagTrack(t, name);
    return Val_unit;
}

CAMLprim value osdl_mixer_track_set_group(value track, value group) {
    MIX_Track* t = osdl_live(track);
    MIX_Group* g = NULL;
    if (Is_block(group)) {
        value handle = Some_val(group);
        g            = osdl_live(handle);
        if (osdl_parent(handle) != osdl_parent(track))
            caml_invalid_argument("The track and group must belong to the same mixer");
    }

    osdl_check(MIX_SetTrackGroup(t, g), "MIX_SetTrackGroup");
    return Val_unit;
}

/* Stop notices. The track's only possible child is its stop watch. */

static void SDLCALL mixer_track_stopped(void* userdata, MIX_Track* track) {
    (void)track;
    SDL_SetAtomicInt(userdata, 1);
}

CAMLprim value osdl_mixer_track_watch_stops(value track) {
    CAMLparam1(track);
    CAMLlocal1(watch);

    watch        = osdl_new_handle(track);
    MIX_Track* t = osdl_live(track);
    if (osdl_cell_val(track)->children) caml_invalid_argument("The track already has a stop watch");

    SDL_AtomicInt* pending = SDL_calloc(1, sizeof(*pending));
    if (!pending) osdl_fail("SDL_calloc");
    if (!MIX_SetTrackStoppedCallback(t, mixer_track_stopped, pending)) {
        char message[1024];
        osdl_error_message(message, sizeof(message), "MIX_SetTrackStoppedCallback");
        SDL_free(pending);
        osdl_raise_error(message);
    }
    CAMLreturn(osdl_publish(watch, pending, "MIX_SetTrackStoppedCallback"));
}

CAMLprim value osdl_mixer_stop_watch_take(value watch) {
    SDL_AtomicInt* pending = osdl_live(watch);
    return Val_bool(SDL_SetAtomicInt(pending, 0) != 0);
}

CAMLprim value osdl_mixer_stop_watch_close(value watch) {
    osdl_cell* cell = osdl_cell_val(watch);
    osdl_require_thread(osdl_cell_thread(cell));
    if (!cell->ptr) return Val_unit;

    /* Removal holds the same track lock as the callback. Do not free the flag
     * or release the child handle if unregistration fails. */
    MIX_Track* t = osdl_live(osdl_parent(watch));
    osdl_check(MIX_SetTrackStoppedCallback(t, NULL, NULL), "MIX_SetTrackStoppedCallback");
    SDL_free(osdl_take(watch));
    return Val_unit;
}
