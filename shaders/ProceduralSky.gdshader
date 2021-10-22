/*========================================================
°                       TimeOfDay.
°                   ======================
°
°   Category: Sky Shaders.
°   -----------------------------------------------------
°   Description:
°       Procedural Sky based on Preetham and Hoffman paper.
°   -----------------------------------------------------
°   Copyright:
°               J. Cuellar 2021. MIT License.
°                   See: LICENSE File.
========================================================*/

shader_type sky;

// Globals.
uniform float _Exposure = 1.3;
uniform float _Tonemap: hint_range(0.0, 1.0) = 0.0;
uniform float _ContrastLevel: hint_range(0.0, 1.0) = 0.3;
uniform vec4 _GroundColor: hint_color = vec4(0.3, 0.3, 0.3, 1.0);

// Rayleigh.
uniform float _AtmosDarkness: hint_range(0.0, 1.0) = 0.5;
uniform float _AtmosSunIntensity = 30.0;
uniform float _AtmosThickness = 1.0;
uniform vec4 _AtmosDayTint: hint_color = vec4(1.0);
uniform vec4 _AtmosHorizonTint: hint_color = vec4(0.980392, 0.635294, 0.462745, 1.0);
uniform vec4 _AtmosNightTint: hint_color = vec4(0.02, 0.03, 0.04, 1.0);
uniform vec3 _AtmosLevelParams = vec3(1.0, 0.0, 0.0);

// MiePhase.
uniform float _AtmosMie = 0.07;
uniform vec4 _AtmosMieTint: hint_color = vec4(1.0);
uniform float _AtmosMieIntensity = 1.0;
uniform float _AtmosMieAnisotropy: hint_range(0.0, 0.9999999) = 0.8;

// Sun Disk.
uniform vec4  _SunDiskTint: hint_color = vec4(0.99, 0.49, 0.22, 1.0);
uniform float _SunDiskIntensity = 10.0;
uniform float _SunDiskSize = 0.022;

// PI.
const float kPI     = 3.1415927;  // π.
const float kTAU    = 6.2831853;  // π * 2.
const float kPIRCP  = 0.3183098;  // 1/π.
const float kPI4    = 12.5663706; // PI(π)*4.
const float kPI4RCP = 0.0795775;  // 1/(PI(π)*4).
const float k3PI16  = 0.0596831;  // 3/(PI(π)*16).

// Zenith Length.
const float RAYLEIGH_ZENITH_LENGTH = 8.4e3;
const float MIE_ZENITH_LENGTH = 1.25e3;

// Beta Ray.
const highp vec3 kBetaRay = vec3(5.807035e-06, 1.356874e-05, 3.312679e-05); // 680, 550, 440
//const vec3 kBetaRay = vec3(6.955633e-6, 1.176226e-05, 2.439022e-05); // 650, 570, 475

const vec3 kBetaMie = vec3(0.000434);

float saturate(float x){
	return clamp(x, 0.0 , 1.0);
}

vec3 saturateRGB(vec3 rgb){
	return clamp(rgb, 0.0, 1.0);
}

// pow3
vec3 contrastLevel(vec3 vec, float level){
	return mix(vec, vec * vec * vec, level);
}

vec3 tonemapPhoto(vec3 color, float exposure, float level){
	color.rgb *= exposure;
	return mix(color.rgb, 1.0 - exp(-color.rgb), level);
}

float sunDisk(vec3 norm, vec3 coords, lowp float size){
	float dist = length(norm - coords);
	return 1.0 - step(size, dist);
}

float rayleighPhase(float mu){
	return k3PI16 * (1.0 + mu * mu);
}

vec3 partialMiePhase(in float g){
	vec3 ret; 
	float g2 = g * g;
	//ret.x = ((1.0 - g2) / (2.0 + g2));
	ret.x = (1.0 - g2);
	ret.y = (1.0 + g2);
	ret.z = (2.0 * g);
	return ret;
}

float miePhase(float mu, float g)
{
	vec3 partial = partialMiePhase(g);
	return (kPI4 * partial.x * ((1.0 + mu * mu) * 
		pow(partial.y - (partial.z * mu), -1.5))) * _AtmosMieIntensity;
}

// Simplifield for more performance.
void simpleOpticalDepth(float y, out float sr, out float sm){
	y = max(0.03, y + 0.03) + _AtmosLevelParams.y;
	y = 1.0 / (y * _AtmosLevelParams.x);
	sr = y * RAYLEIGH_ZENITH_LENGTH;
	sm = y * MIE_ZENITH_LENGTH;
}

// Paper based.
void opticalDepth(float y, out float sr, out float sm){
	y = max(0.0, y);
	y = saturate(y * _AtmosLevelParams.x);
	
	float zenith = acos(y);
	zenith = cos(zenith) + 0.15 * pow(93.885 - ((zenith * 180.0) / kPI), -1.253);
	zenith = 1.0 / (zenith + _AtmosLevelParams.y);
	
	sr = zenith * RAYLEIGH_ZENITH_LENGTH;
	sm = zenith * MIE_ZENITH_LENGTH;
}

vec3 atmosphericScattering(float sr, float sm, float mu, vec3 mult){
	vec3 betaMie = kBetaMie * 0.001 * _AtmosMie;
	vec3 betaRay = kBetaRay * _AtmosThickness;
	
	vec3 extcFactor = saturateRGB(exp(-(betaRay * sr + betaMie * sm)));
	
	float extcFF = mix(saturate(_AtmosThickness * 0.5), 1.0, mult.x);
	vec3 finalExtcFactor = mix(1.0 - extcFactor, (1.0 - extcFactor) * extcFactor, extcFF);
	float rayleighPhase = rayleighPhase(mu);
	vec3 BRT = betaRay * rayleighPhase;
	vec3 BMT = betaMie * miePhase(mu, _AtmosMieAnisotropy);
	BMT *= _AtmosMieIntensity * _AtmosMieTint.rgb;
	
	vec3 BRMT = (BRT + BMT) / (betaRay + betaMie);
	vec3 scatter = _AtmosSunIntensity * (BRMT * finalExtcFactor) * _AtmosDayTint.rgb * mult.y;
	scatter = mix(scatter, scatter * (1.0 - extcFactor), _AtmosDarkness);
	
	vec3 lcol =  mix(_AtmosDayTint.rgb, _AtmosHorizonTint.rgb, mult.x);
	vec3 nscatter = (1.0 - extcFactor) * _AtmosNightTint.rgb;

	return (scatter * lcol) + nscatter;
}

void sky(){
	if (LIGHT0_ENABLED) {
		vec4 anglesMult;
		anglesMult.x = saturate(1.0 - LIGHT0_DIRECTION.y);
		anglesMult.y = saturate(LIGHT0_DIRECTION.y + 0.45);
		anglesMult.z = saturate(-LIGHT0_DIRECTION.y + 0.30);
		anglesMult.w = saturate(LIGHT0_DIRECTION.y);
		
		float y        = dot( vec3(0.0, 1.0, 0.0), EYEDIR);// + _AtmosHorizonOffset;
		float cosTheta = dot(normalize(LIGHT0_DIRECTION), EYEDIR);
		
		// Scattering.
		float sr; float sm; simpleOpticalDepth(y, sr, sm);
		vec3 scatter = atmosphericScattering(sr, sm, cosTheta, anglesMult.xyz);
		
		// Sun Disk.
		scatter += sunDisk(EYEDIR, LIGHT0_DIRECTION, _SunDiskSize) * _SunDiskTint.rgb *
			_SunDiskIntensity * scatter;
		
		// Final Color.
		vec3 finalColor = mix(scatter, _GroundColor.rgb * anglesMult.w, saturate(-y * 100.0) * _GroundColor.a);
		
		// Color Correction.
		finalColor.rgb = tonemapPhoto(finalColor, _Exposure, _Tonemap);
		finalColor.rgb = contrastLevel(finalColor, _ContrastLevel);
		
		COLOR = finalColor;
	}
}