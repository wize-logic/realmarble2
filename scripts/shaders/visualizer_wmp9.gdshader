shader_type spatial;

// Windows Media Player 9 Style Audio Visualizer
// Projects audio-reactive visuals onto walls like the classic WMP visualizers
// Compatible with GL Compatibility renderer

render_mode unshaded, cull_back, depth_draw_opaque;

// Visualization mode: 0=Bars, 1=Scope, 2=Ambience, 3=Battery, 4=Plenoptic
uniform int viz_mode : hint_range(0, 4) = 0;

// Audio spectrum data (32 frequency bands)
uniform float spectrum[32];
uniform float audio_level : hint_range(0.0, 1.0) = 0.0;
uniform float bass_level : hint_range(0.0, 1.0) = 0.0;
uniform float mid_level : hint_range(0.0, 1.0) = 0.0;
uniform float high_level : hint_range(0.0, 1.0) = 0.0;

// Colors (WMP9 style palettes)
uniform vec4 color_primary : source_color = vec4(0.0, 0.7, 1.0, 1.0);
uniform vec4 color_secondary : source_color = vec4(1.0, 0.3, 0.7, 1.0);
uniform vec4 color_accent : source_color = vec4(0.3, 1.0, 0.5, 1.0);
uniform vec4 background_color : source_color = vec4(0.02, 0.02, 0.05, 1.0);

// Settings
uniform float glow_intensity : hint_range(0.0, 3.0) = 1.5;
uniform float animation_speed : hint_range(0.1, 3.0) = 1.0;
uniform float bar_width : hint_range(0.5, 1.0) = 0.85;
uniform float reflection_amount : hint_range(0.0, 1.0) = 0.3;

// Time passed in
uniform float time_offset = 0.0;

// =============================================================================
// NOISE AND UTILITY FUNCTIONS
// =============================================================================

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p, int octaves) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;

	for (int i = 0; i < octaves; i++) {
		value += amplitude * noise(p * frequency);
		amplitude *= 0.5;
		frequency *= 2.0;
	}

	return value;
}

// Get spectrum value with interpolation
float get_spectrum(float x) {
	float idx = x * 31.0;
	int i0 = int(floor(idx));
	int i1 = min(i0 + 1, 31);
	float t = fract(idx);
	return mix(spectrum[i0], spectrum[i1], t);
}

// Smooth spectrum sampling
float get_spectrum_smooth(float x, float smoothness) {
	float total = 0.0;
	float weight_sum = 0.0;
	int samples = 3;

	for (int i = -samples; i <= samples; i++) {
		float offset = float(i) * smoothness / 32.0;
		float weight = 1.0 - abs(float(i)) / float(samples + 1);
		total += get_spectrum(clamp(x + offset, 0.0, 1.0)) * weight;
		weight_sum += weight;
	}

	return total / weight_sum;
}

// =============================================================================
// MODE 0: FREQUENCY BARS (Classic WMP Bars)
// =============================================================================

vec3 render_bars(vec2 uv, float time) {
	vec3 color = background_color.rgb;

	int num_bars = 32;
	float bar_spacing = 1.0 / float(num_bars);

	for (int i = 0; i < num_bars; i++) {
		float bar_x = (float(i) + 0.5) * bar_spacing;
		float bar_center = bar_x;
		float half_width = bar_spacing * bar_width * 0.5;

		// Check if UV is within bar bounds
		if (uv.x >= bar_center - half_width && uv.x <= bar_center + half_width) {
			float spec = spectrum[i];
			float bar_height = spec * 0.85 + 0.02; // Minimum height for visibility

			// Main bar
			if (uv.y < bar_height) {
				// Gradient from primary to accent based on height
				float height_ratio = uv.y / bar_height;
				vec3 bar_color = mix(color_primary.rgb, color_accent.rgb, height_ratio);

				// Add peak glow
				if (uv.y > bar_height - 0.05) {
					bar_color += color_secondary.rgb * glow_intensity * 0.5;
				}

				// Edge glow
				float edge_dist = abs(uv.x - bar_center) / half_width;
				bar_color += color_primary.rgb * (1.0 - edge_dist) * 0.3 * glow_intensity;

				color = bar_color;
			}

			// Reflection below
			if (uv.y > 0.0 && uv.y < bar_height * reflection_amount * 0.3) {
				float ref_y = 1.0 - (uv.y / (bar_height * reflection_amount * 0.3));
				vec3 ref_color = mix(color_primary.rgb, color_accent.rgb, ref_y) * 0.2;
				color = mix(color, ref_color, 0.5 * (1.0 - uv.y / (bar_height * reflection_amount * 0.3)));
			}
		}
	}

	// Add overall bass pulse to background
	color += background_color.rgb * bass_level * 0.5;

	return color;
}

// =============================================================================
// MODE 1: OSCILLOSCOPE / SCOPE (Waveform visualization)
// =============================================================================

vec3 render_scope(vec2 uv, float time) {
	vec3 color = background_color.rgb;

	// Center the waveform
	float center_y = 0.5;

	// Get waveform value at this x position
	float wave_val = get_spectrum_smooth(uv.x, 2.0);

	// Add some sine modulation for visual interest
	wave_val += sin(uv.x * 20.0 + time * 3.0) * mid_level * 0.15;
	wave_val += sin(uv.x * 8.0 - time * 2.0) * bass_level * 0.2;

	// Calculate waveform position
	float wave_y = center_y + (wave_val - 0.5) * 0.8;

	// Distance to waveform line
	float dist = abs(uv.y - wave_y);

	// Main line with glow
	float line_width = 0.008;
	float glow_width = 0.08;

	// Core line
	if (dist < line_width) {
		color = mix(color_primary.rgb, color_accent.rgb, uv.x) * glow_intensity;
	}
	// Glow effect
	else if (dist < glow_width) {
		float glow = 1.0 - (dist - line_width) / (glow_width - line_width);
		glow = pow(glow, 2.0);
		vec3 glow_color = mix(color_primary.rgb, color_secondary.rgb, uv.x);
		color += glow_color * glow * glow_intensity * 0.5;
	}

	// Add trailing echoes
	for (int i = 1; i <= 3; i++) {
		float echo_offset = float(i) * 0.015;
		float echo_wave_y = center_y + (get_spectrum_smooth(uv.x + echo_offset, 2.0) - 0.5) * 0.8;
		float echo_dist = abs(uv.y - echo_wave_y);

		if (echo_dist < glow_width * 0.5) {
			float echo_glow = (1.0 - echo_dist / (glow_width * 0.5)) * (1.0 - float(i) * 0.25);
			color += color_secondary.rgb * echo_glow * 0.2;
		}
	}

	// Center line
	float center_dist = abs(uv.y - center_y);
	if (center_dist < 0.002) {
		color += vec3(0.1);
	}

	return color;
}

// =============================================================================
// MODE 2: AMBIENCE (Flowing particles and gradients)
// =============================================================================

vec3 render_ambience(vec2 uv, float time) {
	vec3 color = background_color.rgb;

	// Create flowing plasma background
	vec2 plasma_uv = uv * 3.0;
	float plasma = 0.0;
	plasma += sin(plasma_uv.x * 2.0 + time) * 0.5;
	plasma += sin(plasma_uv.y * 2.5 + time * 0.7) * 0.5;
	plasma += sin((plasma_uv.x + plasma_uv.y) * 1.5 + time * 0.5) * 0.5;
	plasma += sin(length(plasma_uv - vec2(0.5)) * 3.0 - time) * 0.5;
	plasma = (plasma + 2.0) / 4.0;

	// Modulate with audio
	plasma *= 0.5 + audio_level * 0.5;

	// Color gradient based on plasma and audio
	vec3 plasma_color = mix(color_primary.rgb, color_secondary.rgb, plasma);
	plasma_color = mix(plasma_color, color_accent.rgb, bass_level * 0.5);

	color = plasma_color * 0.3;

	// Add floating particles
	for (int i = 0; i < 20; i++) {
		float fi = float(i);
		float seed = hash(vec2(fi, fi * 0.7));

		// Particle position (float upward, react to bass)
		vec2 particle_pos;
		particle_pos.x = fract(seed + time * 0.05 * (0.5 + seed));
		particle_pos.y = fract(seed * 2.0 + time * 0.1 * (0.3 + seed * 0.7) + bass_level * 0.1);

		// Particle size based on spectrum
		int spec_idx = int(fi) % 32;
		float particle_size = 0.02 + spectrum[spec_idx] * 0.04;

		// Distance to particle
		float dist = length(uv - particle_pos);

		if (dist < particle_size) {
			float intensity = 1.0 - dist / particle_size;
			intensity = pow(intensity, 1.5);

			vec3 particle_color = mix(color_primary.rgb, color_accent.rgb, seed);
			color += particle_color * intensity * glow_intensity * 0.7;
		}

		// Glow around particles
		if (dist < particle_size * 3.0) {
			float glow = 1.0 - dist / (particle_size * 3.0);
			glow = pow(glow, 3.0);
			color += color_secondary.rgb * glow * 0.15;
		}
	}

	// Add vertical streaks on bass hits
	float streak_intensity = pow(bass_level, 2.0) * 0.3;
	float streak = fbm(vec2(uv.x * 10.0, time * 2.0), 3);
	color += color_primary.rgb * streak * streak_intensity;

	return color;
}

// =============================================================================
// MODE 3: BATTERY (Geometric energy patterns)
// =============================================================================

vec3 render_battery(vec2 uv, float time) {
	vec3 color = background_color.rgb;

	// Center coordinates
	vec2 center = vec2(0.5, 0.5);
	vec2 centered_uv = uv - center;

	// Polar coordinates
	float angle = atan(centered_uv.y, centered_uv.x);
	float radius = length(centered_uv);

	// Number of segments based on bass
	float segments = 6.0 + bass_level * 6.0;

	// Rotating energy beams
	for (int i = 0; i < 12; i++) {
		float fi = float(i);
		float beam_angle = (fi / 12.0) * 6.28318 + time * (0.5 + fi * 0.1);

		// Spectrum affects beam length
		int spec_idx = i % 32;
		float beam_length = 0.2 + spectrum[spec_idx] * 0.5;

		// Angle difference
		float angle_diff = abs(mod(angle - beam_angle + 3.14159, 6.28318) - 3.14159);

		// Beam width
		float beam_width = 0.1 + mid_level * 0.1;

		if (angle_diff < beam_width && radius < beam_length) {
			float intensity = (1.0 - angle_diff / beam_width) * (1.0 - radius / beam_length);
			intensity = pow(intensity, 1.5);

			vec3 beam_color = mix(color_primary.rgb, color_accent.rgb, fi / 12.0);
			color += beam_color * intensity * glow_intensity;
		}

		// Beam glow
		if (angle_diff < beam_width * 2.0 && radius < beam_length * 1.2) {
			float glow = (1.0 - angle_diff / (beam_width * 2.0)) * (1.0 - radius / (beam_length * 1.2));
			glow = pow(glow, 3.0);
			color += color_secondary.rgb * glow * 0.3;
		}
	}

	// Center orb pulsing with audio
	float orb_radius = 0.08 + audio_level * 0.05;
	if (radius < orb_radius) {
		float orb_intensity = 1.0 - radius / orb_radius;
		orb_intensity = pow(orb_intensity, 2.0);
		vec3 orb_color = mix(color_accent.rgb, vec3(1.0), orb_intensity);
		color += orb_color * orb_intensity * glow_intensity;
	}

	// Outer ring
	float ring_radius = 0.45 + bass_level * 0.05;
	float ring_width = 0.02 + high_level * 0.02;
	float ring_dist = abs(radius - ring_radius);
	if (ring_dist < ring_width) {
		float ring_intensity = 1.0 - ring_dist / ring_width;
		ring_intensity = pow(ring_intensity, 2.0);

		// Color varies around the ring
		vec3 ring_color = mix(color_primary.rgb, color_secondary.rgb, (angle + 3.14159) / 6.28318);
		color += ring_color * ring_intensity * 0.8;
	}

	// Radial spectrum bars
	for (int i = 0; i < 32; i++) {
		float bar_angle = (float(i) / 32.0) * 6.28318 - 1.5708;
		float angle_diff = abs(mod(angle - bar_angle + 3.14159, 6.28318) - 3.14159);

		if (angle_diff < 0.06) {
			float bar_start = ring_radius + ring_width;
			float bar_length = spectrum[i] * 0.2;

			if (radius > bar_start && radius < bar_start + bar_length) {
				float intensity = (1.0 - angle_diff / 0.06);
				vec3 bar_color = mix(color_primary.rgb, color_accent.rgb, float(i) / 32.0);
				color += bar_color * intensity * 0.6;
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

	// Kaleidoscope effect
	float num_segments = 8.0;
	float segment_angle = 6.28318 / num_segments;
	float mirrored_angle = mod(angle, segment_angle);
	if (mod(floor(angle / segment_angle), 2.0) == 1.0) {
		mirrored_angle = segment_angle - mirrored_angle;
	}

	// Convert back to cartesian for pattern
	vec2 pattern_uv = vec2(cos(mirrored_angle), sin(mirrored_angle)) * radius;
	pattern_uv = pattern_uv * 2.0 + vec2(0.5);

	// Concentric circles pulsing with spectrum
	for (int i = 0; i < 8; i++) {
		float fi = float(i);
		float circle_radius = 0.1 + fi * 0.06;

		// Modulate with spectrum
		int spec_idx = (i * 4) % 32;
		circle_radius += spectrum[spec_idx] * 0.03;

		// Animate
		circle_radius += sin(time * 2.0 + fi) * 0.02 * audio_level;

		float circle_dist = abs(radius - circle_radius);
		float ring_width = 0.015 + spectrum[spec_idx] * 0.01;

		if (circle_dist < ring_width) {
			float intensity = 1.0 - circle_dist / ring_width;
			intensity = pow(intensity, 1.5);

			// Angle-based color variation
			float color_phase = mirrored_angle / segment_angle + time * 0.2 + fi * 0.5;
			vec3 ring_color = mix(color_primary.rgb, color_secondary.rgb, sin(color_phase) * 0.5 + 0.5);
			ring_color = mix(ring_color, color_accent.rgb, cos(color_phase * 2.0) * 0.3 + 0.3);

			color += ring_color * intensity * glow_intensity;
		}
	}

	// Radial lines
	float num_lines = 16.0;
	float line_angle = 6.28318 / num_lines;
	float nearest_line = round(angle / line_angle) * line_angle;
	float line_dist = abs(angle - nearest_line);

	if (line_dist < 0.03) {
		int line_idx = int(round(angle / line_angle)) % 32;
		float line_intensity = spectrum[line_idx] * (1.0 - line_dist / 0.03);
		line_intensity *= (1.0 - radius * 1.5);

		if (line_intensity > 0.0) {
			color += color_accent.rgb * line_intensity * 0.5;
		}
	}

	// Center glow
	float center_glow = exp(-radius * 8.0) * (0.5 + audio_level * 0.5);
	vec3 center_color = mix(color_primary.rgb, vec3(1.0), center_glow);
	color += center_color * center_glow * glow_intensity;

	// Spinning dots at intersections
	for (int ring = 0; ring < 4; ring++) {
		float ring_r = 0.15 + float(ring) * 0.1;
		int num_dots = 8 + ring * 4;

		for (int dot = 0; dot < num_dots; dot++) {
			if (dot >= 20) break; // Limit for performance

			float dot_angle = (float(dot) / float(num_dots)) * 6.28318 + time * (0.5 - float(ring) * 0.1);
			vec2 dot_pos = vec2(cos(dot_angle), sin(dot_angle)) * ring_r;

			float dot_dist = length(centered_uv - dot_pos);
			int spec_idx = (ring * 8 + dot) % 32;
			float dot_size = 0.015 + spectrum[spec_idx] * 0.02;

			if (dot_dist < dot_size) {
				float dot_intensity = 1.0 - dot_dist / dot_size;
				dot_intensity = pow(dot_intensity, 2.0);

				vec3 dot_color = mix(color_secondary.rgb, color_accent.rgb, float(dot) / float(num_dots));
				color += dot_color * dot_intensity * 0.8;
			}
		}
	}

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

	// Add subtle vignette
	vec2 vignette_uv = uv * (1.0 - uv);
	float vignette = pow(vignette_uv.x * vignette_uv.y * 15.0, 0.25);
	final_color *= vignette;

	// HDR bloom-like effect (brighten already bright areas)
	vec3 bloom = max(final_color - vec3(0.5), vec3(0.0));
	final_color += bloom * 0.5;

	// Clamp final output
	ALBEDO = clamp(final_color, vec3(0.0), vec3(2.0));
}
