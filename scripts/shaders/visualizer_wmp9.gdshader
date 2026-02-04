shader_type canvas_item;

// Enhanced Windows Media Player 9 Style Audio Visualizer
// Beautiful, smooth audio-reactive visuals with modern effects

// Visualization mode: 0=Bars, 1=Scope, 2=Ambience, 3=Battery, 4=Plenoptic
uniform int viz_mode = 0;

// Audio spectrum data (32 frequency bands packed into 32x1 textures)
uniform sampler2D spectrum_tex : filter_nearest, repeat_disable;
uniform sampler2D peak_tex : filter_nearest, repeat_disable;
uniform float audio_level : hint_range(0.0, 1.0) = 0.0;
uniform float bass_level : hint_range(0.0, 1.0) = 0.0;
uniform float mid_level : hint_range(0.0, 1.0) = 0.0;
uniform float high_level : hint_range(0.0, 1.0) = 0.0;
uniform float beat_intensity : hint_range(0.0, 1.0) = 0.0;

// Colors (WMP9 style palettes)
uniform vec4 color_primary = vec4(0.0, 0.7, 1.0, 1.0);
uniform vec4 color_secondary = vec4(1.0, 0.3, 0.7, 1.0);
uniform vec4 color_accent = vec4(0.3, 1.0, 0.5, 1.0);
uniform vec4 background_color = vec4(0.02, 0.02, 0.05, 1.0);

// Settings
uniform float glow_intensity : hint_range(0.0, 3.0) = 1.5;
uniform float animation_speed : hint_range(0.1, 3.0) = 1.0;
uniform float bar_width : hint_range(0.5, 1.0) = 0.85;
uniform float reflection_amount : hint_range(0.0, 1.0) = 0.3;

// Time passed in
uniform float time_offset = 0.0;

// Constants
const float PI = 3.14159265359;
const float TAU = 6.28318530718;

// =============================================================================
// NOISE AND UTILITY FUNCTIONS
// =============================================================================

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	// Smooth interpolation
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

	float a = hash3(i);
	float b = hash3(i + vec3(1.0, 0.0, 0.0));
	float c = hash3(i + vec3(0.0, 1.0, 0.0));
	float d = hash3(i + vec3(1.0, 1.0, 0.0));
	float e = hash3(i + vec3(0.0, 0.0, 1.0));
	float f1 = hash3(i + vec3(1.0, 0.0, 1.0));
	float g = hash3(i + vec3(0.0, 1.0, 1.0));
	float h = hash3(i + vec3(1.0, 1.0, 1.0));

	float z1 = mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
	float z2 = mix(mix(e, f1, f.x), mix(g, h, f.x), f.y);
	return mix(z1, z2, f.z);
}

float fbm(vec2 p, int octaves) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;

	for (int i = 0; i < 4; i++) {
		if (i >= octaves) break;
		value += amplitude * noise(p * frequency);
		amplitude *= 0.5;
		frequency *= 2.0;
	}

	return value;
}

// Smooth minimum for blending shapes
float smin(float a, float b, float k) {
	float h = max(k - abs(a - b), 0.0) / k;
	return min(a, b) - h * h * k * 0.25;
}

// Sample a single spectrum band by index (0-31)
float sample_spectrum(int idx) {
	return texture(spectrum_tex, vec2((float(idx) + 0.5) / 32.0, 0.5)).r;
}

// Sample a single peak band by index (0-31)
float sample_peak(int idx) {
	return texture(peak_tex, vec2((float(idx) + 0.5) / 32.0, 0.5)).r;
}

// Get spectrum value with smooth interpolation (x = 0.0 to 1.0)
float get_spectrum(float x) {
	return texture(spectrum_tex, vec2(clamp(x, 0.0, 1.0), 0.5)).r;
}

// Get peak spectrum with interpolation (x = 0.0 to 1.0)
float get_peak(float x) {
	return texture(peak_tex, vec2(clamp(x, 0.0, 1.0), 0.5)).r;
}

// Smooth spectrum sampling with wider kernel
float get_spectrum_smooth(float x, float smoothness) {
	float total = 0.0;
	float weight_sum = 0.0;

	for (int i = -5; i <= 5; i++) {
		float offset = float(i) * smoothness / 32.0;
		float weight = exp(-float(i * i) / (2.0 * smoothness * smoothness));
		total += get_spectrum(x + offset) * weight;
		weight_sum += weight;
	}

	return total / weight_sum;
}

// Soft glow function with customizable falloff
float soft_glow(float dist, float radius, float softness) {
	return pow(max(0.0, 1.0 - dist / radius), softness);
}

// HSV to RGB conversion for color cycling
vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// =============================================================================
// MODE 0: FREQUENCY BARS (Enhanced with rounded tops and peaks)
// =============================================================================

vec3 render_bars(vec2 uv, float time) {
	vec3 color = background_color.rgb;

	int num_bars = 32;
	float bar_spacing = 1.0 / float(num_bars);
	float half_spacing = bar_spacing * 0.5;

	// Background glow based on audio
	float bg_glow = audio_level * 0.15;
	color += mix(color_primary.rgb, color_secondary.rgb, uv.x) * bg_glow * (1.0 - uv.y);

	// Beat pulse effect
	if (beat_intensity > 0.0) {
		float pulse = beat_intensity * 0.2;
		color += color_accent.rgb * pulse * (1.0 - length(uv - vec2(0.5)) * 1.5);
	}

	for (int i = 0; i < num_bars; i++) {
		float fi = float(i);
		float bar_x = (fi + 0.5) * bar_spacing;
		float half_width = bar_spacing * bar_width * 0.5;

		float dist_to_bar = abs(uv.x - bar_x);

		// Only process if within bar influence area (optimization + glow)
		if (dist_to_bar < half_width * 3.0) {
			float spec = sample_spectrum(i);
			float peak = sample_peak(i);
			float bar_height = spec * 0.82 + 0.03;

			// Normalized position within bar
			float x_in_bar = (uv.x - (bar_x - half_width)) / (half_width * 2.0);

			// Rounded top calculation
			float round_radius = half_width * 0.8;
			float top_center_y = bar_height - round_radius;
			float effective_height = bar_height;

			if (uv.y > top_center_y && dist_to_bar < half_width) {
				// Check if in rounded cap area
				vec2 cap_center = vec2(bar_x, top_center_y);
				float cap_dist = length(vec2(uv.x, uv.y) - cap_center);
				if (cap_dist > round_radius) {
					effective_height = -1.0; // Outside rounded cap
				}
			}

			// Main bar body
			if (dist_to_bar < half_width && uv.y < effective_height && uv.y > 0.0) {
				// Height-based gradient
				float height_ratio = uv.y / bar_height;

				// Smooth color transition
				vec3 bar_color = mix(color_primary.rgb, color_secondary.rgb, height_ratio);
				bar_color = mix(bar_color, color_accent.rgb, pow(height_ratio, 2.0) * 0.5);

				// Inner highlight (3D effect)
				float inner_highlight = 1.0 - abs(x_in_bar - 0.5) * 1.5;
				inner_highlight = pow(max(0.0, inner_highlight), 1.5);
				bar_color += vec3(0.2) * inner_highlight;

				// Edge darkening for depth
				float edge = 1.0 - pow(abs(x_in_bar - 0.5) * 2.0, 3.0) * 0.3;
				bar_color *= edge;

				// Top glow
				if (uv.y > bar_height - 0.08) {
					float top_glow = (uv.y - (bar_height - 0.08)) / 0.08;
					bar_color += color_accent.rgb * top_glow * glow_intensity * 0.6;
				}

				color = bar_color;
			}

			// Bar glow (soft light around bars)
			float glow_dist = max(dist_to_bar - half_width, 0.0);
			if (uv.y < bar_height + 0.05 && uv.y > 0.0) {
				float glow = soft_glow(glow_dist, half_width * 1.5, 2.5);
				glow *= (1.0 - uv.y / (bar_height + 0.1));
				vec3 glow_color = mix(color_primary.rgb, color_accent.rgb, uv.y / bar_height);
				color += glow_color * glow * glow_intensity * 0.25;
			}

			// Peak indicator (floating marker)
			if (peak > spec + 0.02) {
				float peak_y = peak * 0.82 + 0.03;
				float peak_dist = abs(uv.y - peak_y);
				if (peak_dist < 0.015 && dist_to_bar < half_width) {
					float peak_intensity = 1.0 - peak_dist / 0.015;
					peak_intensity = pow(peak_intensity, 1.5);
					color = mix(color, color_accent.rgb * 1.5, peak_intensity);
				}
				// Peak glow
				if (peak_dist < 0.04 && dist_to_bar < half_width * 1.2) {
					float peak_glow = soft_glow(peak_dist, 0.04, 2.0);
					color += color_accent.rgb * peak_glow * 0.3;
				}
			}

			// Reflection (subtle mirror effect)
			if (uv.y < bar_height * reflection_amount * 0.25 && dist_to_bar < half_width) {
				float ref_y = uv.y / (bar_height * reflection_amount * 0.25);
				float ref_intensity = (1.0 - ref_y) * 0.25;
				vec3 ref_color = mix(color_primary.rgb, color_secondary.rgb, 1.0 - ref_y) * ref_intensity;
				color = mix(color, ref_color, ref_intensity * 0.6);
			}
		}
	}

	// Floor reflection line
	float floor_line = smoothstep(0.003, 0.0, abs(uv.y - 0.002));
	color += vec3(0.15) * floor_line * audio_level;

	return color;
}

// =============================================================================
// MODE 1: OSCILLOSCOPE / SCOPE (Enhanced waveform with trails)
// =============================================================================

vec3 render_scope(vec2 uv, float time) {
	vec3 color = background_color.rgb;

	// Subtle animated background
	float bg_noise = fbm(uv * 3.0 + vec2(time * 0.1, 0.0), 2) * 0.05;
	color += mix(color_primary.rgb, color_secondary.rgb, uv.x) * bg_noise * audio_level;

	float center_y = 0.5;

	// Multiple wave layers for depth
	for (int layer = 2; layer >= 0; layer--) {
		float layer_offset = float(layer) * 0.02;
		float layer_alpha = 1.0 - float(layer) * 0.3;
		float layer_width = 1.0 + float(layer) * 0.5;

		// Get waveform value at this x position
		float wave_val = get_spectrum_smooth(uv.x + layer_offset, 1.5);

		// Add flowing sine modulation
		wave_val += sin(uv.x * 25.0 + time * 4.0 - float(layer)) * mid_level * 0.12;
		wave_val += sin(uv.x * 10.0 - time * 2.5 + float(layer) * 0.5) * bass_level * 0.18;
		wave_val += sin(uv.x * 40.0 + time * 6.0) * high_level * 0.06;

		// Calculate waveform position
		float wave_y = center_y + (wave_val - 0.5) * 0.75;

		// Distance to waveform line
		float dist = abs(uv.y - wave_y);

		// Line width varies with audio
		float line_width = 0.006 * layer_width + audio_level * 0.004;
		float glow_width = 0.06 * layer_width + audio_level * 0.03;

		// Color based on layer and position
		vec3 wave_color = mix(color_primary.rgb, color_secondary.rgb, uv.x);
		wave_color = mix(wave_color, color_accent.rgb, float(layer) * 0.3);

		// Core line with smooth anti-aliasing
		float line_intensity = smoothstep(line_width, line_width * 0.3, dist);
		color += wave_color * line_intensity * glow_intensity * layer_alpha;

		// Glow effect with exponential falloff
		float glow = exp(-dist * dist / (glow_width * glow_width * 0.5));
		color += wave_color * glow * glow_intensity * 0.3 * layer_alpha;
	}

	// Trailing echoes with fade
	for (int i = 1; i <= 5; i++) {
		float echo_offset = float(i) * 0.025;
		float echo_alpha = 1.0 - float(i) * 0.18;

		float echo_val = get_spectrum_smooth(uv.x + echo_offset, 2.0);
		echo_val += sin((uv.x + echo_offset) * 20.0 + time * 3.0 - float(i) * 0.5) * mid_level * 0.1;
		float echo_y = center_y + (echo_val - 0.5) * 0.7;

		float echo_dist = abs(uv.y - echo_y);
		float echo_glow = exp(-echo_dist * echo_dist / 0.002);
		color += color_secondary.rgb * echo_glow * echo_alpha * 0.15;
	}

	// Center reference line (subtle)
	float center_dist = abs(uv.y - center_y);
	float center_line = smoothstep(0.002, 0.0005, center_dist);
	color += vec3(0.08) * center_line;

	// Grid lines (very subtle)
	float grid_x = smoothstep(0.002, 0.0, abs(mod(uv.x, 0.1) - 0.05) - 0.048);
	float grid_y = smoothstep(0.002, 0.0, abs(mod(uv.y, 0.1) - 0.05) - 0.048);
	color += vec3(0.03) * max(grid_x, grid_y);

	return color;
}

// =============================================================================
// MODE 2: AMBIENCE (Layered particles and plasma)
// =============================================================================

vec3 render_ambience(vec2 uv, float time) {
	vec3 color = background_color.rgb;

	// Multi-layer plasma background
	for (int layer = 0; layer < 3; layer++) {
		float fl = float(layer);
		float layer_speed = 1.0 - fl * 0.3;
		float layer_scale = 2.0 + fl * 1.5;

		vec2 plasma_uv = uv * layer_scale + vec2(time * 0.1 * layer_speed, fl);

		float plasma = 0.0;
		plasma += sin(plasma_uv.x * 2.5 + time * layer_speed) * 0.5;
		plasma += sin(plasma_uv.y * 3.0 + time * 0.8 * layer_speed) * 0.5;
		plasma += sin((plasma_uv.x + plasma_uv.y) * 2.0 + time * 0.6) * 0.5;
		plasma += sin(length(plasma_uv - vec2(0.5 + fl * 0.2)) * 4.0 - time * layer_speed) * 0.5;
		plasma = (plasma + 2.0) / 4.0;

		// Modulate with audio bands
		float band_mod = layer == 0 ? bass_level : (layer == 1 ? mid_level : high_level);
		plasma *= 0.4 + band_mod * 0.6;

		// Layer color
		vec3 layer_color = layer == 0 ? color_primary.rgb :
						   (layer == 1 ? color_secondary.rgb : color_accent.rgb);

		color += layer_color * plasma * (0.15 - fl * 0.03);
	}

	// Nebula-like clouds
	float nebula = fbm(uv * 4.0 + vec2(time * 0.05, time * 0.03), 4);
	nebula = pow(nebula, 1.5) * audio_level;
	vec3 nebula_color = mix(color_primary.rgb, color_accent.rgb, nebula);
	color += nebula_color * nebula * 0.3;

	// Floating particles with trails
	for (int i = 0; i < 30; i++) {
		float fi = float(i);
		float seed = hash(vec2(fi, fi * 0.7));
		float seed2 = hash(vec2(fi * 1.3, fi * 0.5));

		// Particle motion with audio influence
		vec2 particle_pos;
		float speed_mod = 0.5 + seed * 0.5;
		particle_pos.x = fract(seed + time * 0.03 * speed_mod + bass_level * 0.02 * sin(time + fi));
		particle_pos.y = fract(seed2 + time * 0.05 * speed_mod + seed * 0.2);

		// Particle size based on spectrum and distance
		int spec_idx = int(fi) % 32;
		float base_size = 0.008 + seed * 0.015;
		float audio_size = sample_spectrum(spec_idx) * 0.025;
		float particle_size = base_size + audio_size;

		// Distance to particle
		float dist = length(uv - particle_pos);

		// Particle core
		if (dist < particle_size) {
			float intensity = 1.0 - dist / particle_size;
			intensity = pow(intensity, 2.0);

			vec3 particle_color = mix(color_primary.rgb, color_accent.rgb, seed);
			particle_color = mix(particle_color, vec3(1.0), intensity * 0.5);
			color += particle_color * intensity * glow_intensity * 0.8;
		}

		// Particle glow (soft halo)
		float glow_size = particle_size * 4.0;
		if (dist < glow_size) {
			float glow = exp(-dist * dist / (glow_size * glow_size * 0.3));
			vec3 glow_color = mix(color_secondary.rgb, color_primary.rgb, seed2);
			color += glow_color * glow * 0.15;
		}

		// Particle trail
		float trail_length = 0.05 + sample_spectrum(spec_idx) * 0.03;
		vec2 trail_dir = vec2(-0.03 * speed_mod, -0.05 * speed_mod);
		for (int t = 1; t <= 5; t++) {
			vec2 trail_pos = particle_pos + trail_dir * float(t) * 0.2;
			float trail_dist = length(uv - trail_pos);
			float trail_size = particle_size * (1.0 - float(t) * 0.15);
			if (trail_dist < trail_size * 2.0) {
				float trail_glow = exp(-trail_dist * trail_dist / (trail_size * trail_size * 2.0));
				color += color_secondary.rgb * trail_glow * 0.08 * (1.0 - float(t) * 0.18);
			}
		}
	}

	// Bass-reactive vertical energy streaks
	float streak_intensity = pow(bass_level, 1.5) * 0.4;
	if (streak_intensity > 0.01) {
		float streak = fbm(vec2(uv.x * 15.0, time * 3.0), 3);
		streak = pow(streak, 2.0);
		vec3 streak_color = mix(color_primary.rgb, color_accent.rgb, uv.y);
		color += streak_color * streak * streak_intensity * (1.0 - abs(uv.y - 0.5) * 1.5);
	}

	// Beat flash
	if (beat_intensity > 0.1) {
		float flash = beat_intensity * 0.3;
		color += color_accent.rgb * flash * (1.0 - length(uv - vec2(0.5)) * 1.2);
	}

	return color;
}

// =============================================================================
// MODE 3: BATTERY (Geometric energy patterns)
// =============================================================================

vec3 render_battery(vec2 uv, float time) {
	vec3 color = background_color.rgb;

	vec2 center = vec2(0.5, 0.5);
	vec2 centered_uv = uv - center;

	float angle = atan(centered_uv.y, centered_uv.x);
	float radius = length(centered_uv);

	// Background energy field
	float field = fbm(centered_uv * 5.0 + vec2(time * 0.2), 3);
	field *= audio_level * 0.2;
	color += mix(color_primary.rgb, color_secondary.rgb, field) * field;

	// Rotating energy beams with smooth edges
	int num_beams = 12;
	for (int i = 0; i < num_beams; i++) {
		float fi = float(i);
		float beam_angle = (fi / float(num_beams)) * TAU + time * (0.4 + fi * 0.05);

		// Spectrum affects beam properties
		int spec_idx = i % 32;
		float beam_length = 0.15 + sample_spectrum(spec_idx) * 0.55;
		float beam_width = 0.08 + mid_level * 0.06;

		// Angle difference with smooth wrapping
		float angle_diff = abs(mod(angle - beam_angle + PI, TAU) - PI);

		// Smooth beam edges
		float beam_intensity = smoothstep(beam_width, beam_width * 0.3, angle_diff);
		beam_intensity *= smoothstep(beam_length, beam_length * 0.7, radius);
		beam_intensity *= smoothstep(0.0, 0.08, radius); // Fade near center

		if (beam_intensity > 0.0) {
			// Color gradient along beam
			float color_phase = fi / float(num_beams);
			vec3 beam_color = mix(color_primary.rgb, color_accent.rgb, color_phase);
			beam_color = mix(beam_color, color_secondary.rgb, radius / beam_length);

			// Inner glow
			float inner_glow = pow(beam_intensity, 1.5);
			beam_color += vec3(0.3) * inner_glow;

			color += beam_color * beam_intensity * glow_intensity * 0.7;
		}

		// Beam glow/halo
		float halo_intensity = smoothstep(beam_width * 2.5, beam_width, angle_diff);
		halo_intensity *= smoothstep(beam_length * 1.3, beam_length * 0.5, radius);
		halo_intensity *= smoothstep(0.0, 0.1, radius);
		color += color_secondary.rgb * halo_intensity * 0.12;
	}

	// Pulsing center orb
	float orb_radius = 0.06 + audio_level * 0.04 + beat_intensity * 0.02;
	float orb_glow_radius = orb_radius * 3.0;

	// Orb core
	if (radius < orb_radius) {
		float orb_intensity = 1.0 - radius / orb_radius;
		orb_intensity = pow(orb_intensity, 1.5);
		vec3 orb_color = mix(color_accent.rgb, vec3(1.0), orb_intensity * 0.8);
		color = mix(color, orb_color, orb_intensity);
	}

	// Orb glow
	float orb_glow = exp(-radius * radius / (orb_glow_radius * orb_glow_radius * 0.15));
	color += color_accent.rgb * orb_glow * glow_intensity * 0.5;

	// Multiple concentric rings
	for (int ring = 0; ring < 3; ring++) {
		float fr = float(ring);
		float ring_radius = 0.2 + fr * 0.12 + bass_level * 0.03 * (1.0 + fr * 0.5);
		float ring_width = 0.015 + high_level * 0.01;

		float ring_dist = abs(radius - ring_radius);
		float ring_intensity = smoothstep(ring_width, ring_width * 0.2, ring_dist);

		// Animated color around ring
		float ring_hue = (angle + PI) / TAU + time * 0.1 * (1.0 + fr * 0.3);
		vec3 ring_color = mix(color_primary.rgb, color_secondary.rgb, fract(ring_hue));

		// Add spectrum modulation
		int ring_spec_idx = int(((angle + PI) / TAU) * 32.0) % 32;
		ring_intensity *= 0.5 + sample_spectrum(ring_spec_idx) * 0.5;

		color += ring_color * ring_intensity * 0.8;

		// Ring glow
		float ring_glow = exp(-ring_dist * ring_dist / (ring_width * ring_width * 8.0));
		color += color_secondary.rgb * ring_glow * 0.1;
	}

	// Outer radial spectrum bars
	float bar_start = 0.42;
	for (int i = 0; i < 32; i++) {
		float bar_angle = (float(i) / 32.0) * TAU - PI * 0.5;
		float angle_diff = abs(mod(angle - bar_angle + PI, TAU) - PI);

		float bar_angular_width = 0.05;
		if (angle_diff < bar_angular_width) {
			float bar_length = sample_spectrum(i) * 0.15;
			if (radius > bar_start && radius < bar_start + bar_length) {
				float intensity = smoothstep(bar_angular_width, bar_angular_width * 0.3, angle_diff);
				intensity *= smoothstep(bar_start, bar_start + 0.02, radius);
				intensity *= smoothstep(bar_start + bar_length, bar_start + bar_length - 0.02, radius);

				vec3 bar_color = mix(color_primary.rgb, color_accent.rgb, float(i) / 32.0);
				color += bar_color * intensity * 0.7;
			}
		}
	}

	return color;
}

// =============================================================================
// MODE 4: PLENOPTIC (Circular kaleidoscope patterns)
// =============================================================================

vec3 render_plenoptic(vec2 uv, float time) {
	vec3 color = background_color.rgb;

	vec2 center = vec2(0.5, 0.5);
	vec2 centered_uv = uv - center;

	float angle = atan(centered_uv.y, centered_uv.x);
	float radius = length(centered_uv);

	// Kaleidoscope effect with smooth transitions
	float num_segments = 8.0;
	float segment_angle = TAU / num_segments;
	float segment_idx = floor(angle / segment_angle + 0.5);
	float mirrored_angle = mod(angle, segment_angle);
	if (mod(segment_idx, 2.0) == 1.0) {
		mirrored_angle = segment_angle - mirrored_angle;
	}

	// Background swirl
	float swirl_angle = angle + radius * 3.0 * sin(time * 0.3) + time * 0.2;
	float swirl = sin(swirl_angle * 5.0 + time) * 0.5 + 0.5;
	swirl *= audio_level * 0.15;
	color += mix(color_primary.rgb, color_secondary.rgb, swirl) * swirl;

	// Concentric pulsing rings
	for (int i = 0; i < 10; i++) {
		float fi = float(i);
		float base_radius = 0.05 + fi * 0.045;

		// Spectrum modulation
		int spec_idx = (i * 3) % 32;
		float spec_mod = sample_spectrum(spec_idx);
		float circle_radius = base_radius + spec_mod * 0.02;

		// Time-based animation
		circle_radius += sin(time * 2.5 + fi * 0.8) * 0.015 * audio_level;

		float ring_width = 0.012 + spec_mod * 0.008;
		float circle_dist = abs(radius - circle_radius);

		// Smooth ring with glow
		float ring_intensity = smoothstep(ring_width, ring_width * 0.15, circle_dist);

		if (ring_intensity > 0.0) {
			// Angle-based color variation with kaleidoscope
			float color_phase = mirrored_angle / segment_angle + time * 0.15 + fi * 0.4;
			vec3 ring_color = mix(color_primary.rgb, color_secondary.rgb, sin(color_phase * PI) * 0.5 + 0.5);
			ring_color = mix(ring_color, color_accent.rgb, cos(color_phase * PI * 2.0) * 0.25 + 0.25);

			// Brightness variation
			ring_color *= 0.8 + spec_mod * 0.4;

			color += ring_color * ring_intensity * glow_intensity * 0.8;
		}

		// Soft outer glow
		float glow = exp(-circle_dist * circle_dist / (ring_width * ring_width * 6.0));
		color += color_secondary.rgb * glow * 0.06;
	}

	// Radial lines with spectrum
	float num_lines = 32.0;
	float line_angle = TAU / num_lines;
	for (int i = 0; i < 32; i++) {
		float fi = float(i);
		float target_angle = fi * line_angle - PI;
		float angle_diff = abs(mod(angle - target_angle + PI, TAU) - PI);

		float line_width = 0.025 + sample_spectrum(i) * 0.015;
		float line_intensity = smoothstep(line_width, line_width * 0.2, angle_diff);
		line_intensity *= sample_spectrum(i);
		line_intensity *= smoothstep(0.5, 0.1, radius); // Fade at edges

		if (line_intensity > 0.01) {
			vec3 line_color = mix(color_accent.rgb, color_primary.rgb, fi / 32.0);
			color += line_color * line_intensity * 0.4;
		}
	}

	// Center mandala glow
	float center_glow = exp(-radius * radius / 0.015) * (0.6 + audio_level * 0.4);
	vec3 center_color = mix(color_primary.rgb, vec3(1.0), center_glow * 0.7);
	color += center_color * center_glow * glow_intensity * 0.8;

	// Spinning dots at ring intersections
	for (int ring = 0; ring < 5; ring++) {
		float ring_r = 0.1 + float(ring) * 0.08;
		int num_dots = 8 + ring * 6;
		float dot_angular_speed = 0.4 - float(ring) * 0.08;

		for (int dot = 0; dot < 38; dot++) {
			if (dot >= num_dots) break;

			float dot_angle = (float(dot) / float(num_dots)) * TAU + time * dot_angular_speed;
			vec2 dot_pos = vec2(cos(dot_angle), sin(dot_angle)) * ring_r;

			float dot_dist = length(centered_uv - dot_pos);
			int spec_idx = (ring * 8 + dot) % 32;
			float dot_size = 0.012 + sample_spectrum(spec_idx) * 0.018;

			// Dot core
			if (dot_dist < dot_size) {
				float dot_intensity = 1.0 - dot_dist / dot_size;
				dot_intensity = pow(dot_intensity, 1.8);

				vec3 dot_color = mix(color_secondary.rgb, color_accent.rgb, float(dot) / float(num_dots));
				dot_color = mix(dot_color, vec3(1.0), dot_intensity * 0.4);
				color += dot_color * dot_intensity * 0.9;
			}

			// Dot glow
			float dot_glow = exp(-dot_dist * dot_dist / (dot_size * dot_size * 4.0));
			color += color_secondary.rgb * dot_glow * 0.12;
		}
	}

	return color;
}

// =============================================================================
// POST-PROCESSING EFFECTS
// =============================================================================

vec3 apply_post_processing(vec3 color, vec2 uv, float time) {
	// Chromatic aberration (subtle, increases with beat)
	float aberration_amount = 0.002 + beat_intensity * 0.003;
	vec2 aberration_dir = normalize(uv - vec2(0.5)) * aberration_amount;
	// Note: We can't actually sample other pixels in fragment shader without textures
	// So we'll simulate it with color shifting based on position
	float edge_dist = length(uv - vec2(0.5)) * 2.0;
	color.r *= 1.0 + aberration_dir.x * edge_dist * 10.0;
	color.b *= 1.0 - aberration_dir.x * edge_dist * 10.0;

	// Film grain (very subtle)
	float grain = hash(uv * 1000.0 + vec2(time * 100.0, 0.0)) * 0.03;
	color += vec3(grain) * (0.3 + audio_level * 0.2);

	// Subtle scanlines
	float scanline = sin(uv.y * 800.0) * 0.02 + 0.98;
	color *= scanline;

	// Vignette (enhanced)
	vec2 vignette_uv = uv * (1.0 - uv);
	float vignette = pow(vignette_uv.x * vignette_uv.y * 16.0, 0.3);
	vignette = mix(0.3, 1.0, vignette);
	color *= vignette;

	// HDR bloom simulation
	vec3 bloom = max(color - vec3(0.6), vec3(0.0));
	color += bloom * 0.6 * glow_intensity;

	// Subtle color grading (increase saturation slightly)
	float luminance = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(vec3(luminance), color, 1.15);

	return color;
}

// =============================================================================
// MAIN FRAGMENT
// =============================================================================

void fragment() {
	vec2 uv = UV;

	// Flip Y for proper orientation
	uv.y = 1.0 - uv.y;

	float time = TIME * animation_speed + time_offset;

	vec3 final_color = vec3(0.0);

	// Select visualization mode
	if (viz_mode == 0) {
		final_color = render_bars(uv, time);
	} else if (viz_mode == 1) {
		final_color = render_scope(uv, time);
	} else if (viz_mode == 2) {
		final_color = render_ambience(uv, time);
	} else if (viz_mode == 3) {
		final_color = render_battery(uv, time);
	} else if (viz_mode == 4) {
		final_color = render_plenoptic(uv, time);
	}

	// Apply post-processing
	final_color = apply_post_processing(final_color, uv, time);

	// Clamp final output
	COLOR = vec4(clamp(final_color, vec3(0.0), vec3(1.0)), 1.0);
}
