// Basic Texture Shader

#type vertex
#version 450 core

layout(location = 0) in vec3 a_Position;

layout(std140, binding = 30) uniform Cameras
{
	mat4 u_ViewProjection;
};

layout(location = 0) out vec3 v_Position;

void main()
{
	v_Position = a_Position;
	gl_Position = u_ViewProjection * vec4(a_Position, 1.0);
}

#type fragment
#version 450 core

layout(location = 0) in vec3 v_Position;

layout(location = 0) out vec4 FragColor;

layout(binding = 0) uniform samplerCube u_EnvironmentMap;
layout(std140, binding = 31) uniform RoughnessData
{
	float roughness;
};

const float PI = 3.14159265359;

float DistributionGGX(vec3 N, vec3 H, float roughness)
{
    float a = roughness*roughness;
    float a2 = a*a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH*NdotH;

    float nom   = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return nom / denom;
}

float RadicalInverse_VdC(uint bits) 
{
     bits = (bits << 16u) | (bits >> 16u);
     bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
     bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
     bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
     bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
     return float(bits) * 2.3283064365386963e-10; // / 0x100000000
}

vec2 Hammersley(uint i, uint N)
{
	return vec2(float(i)/float(N), RadicalInverse_VdC(i));
}

vec3 ImportanceSampleGGX(vec2 Xi, vec3 N, float roughness)
{
	float a = roughness * roughness;

	float phi = 2.0 * PI * Xi.x;
	float cosTheta = sqrt((1.0 - Xi.y) / (1.0 + (a*a - 1.0) * Xi.y));
	float sinTheta = sqrt(1.0 - cosTheta * cosTheta);

	// from spherical coordinates to cartesian coordinates
	vec3 H;
    H.x = cos(phi) * sinTheta;
    H.y = sin(phi) * sinTheta;
    H.z = cosTheta;

	// from tangent-space vector to world-space sample vector
    vec3 up        = abs(N.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent   = normalize(cross(up, N));
    vec3 bitangent = cross(N, tangent);

    vec3 sampleVec = tangent * H.x + bitangent * H.y + N * H.z;
    return normalize(sampleVec);
}

void main()
{
	vec3 normal = normalize(v_Position);
	vec3 reflictDir = normal;
	vec3 viewDir = normal;
	
	const uint sample_count = 1024u;
	vec3 prefilteredColor = vec3(0.0);
    float totalWeight = 0.0;

	for (uint i = 0u; i < sample_count; ++i)
	{
		// generates a sample vector that's biased towards the preferred alignment direction (importance sampling).
		vec2 Xi = Hammersley(i, sample_count);
		vec3 halfVec = ImportanceSampleGGX(Xi, normal, roughness);
		vec3 lightDir = normalize(2.0 * dot(viewDir, halfVec) * halfVec - viewDir);

		float NdotL = max(dot(normal, lightDir), 0.0);
		if (NdotL > 0.0)
		{
			float D = DistributionGGX(normal, halfVec, roughness);
			float NdotH = max(dot(normal, halfVec), 0.0);
            float HdotV = max(dot(halfVec, viewDir), 0.0);
            float pdf = D * NdotH / (4.0 * HdotV) + 0.0001;

			float resolution = 512.0; // resolution of source cubemap (per face)
            float saTexel  = 4.0 * PI / (6.0 * resolution * resolution);
            float saSample = 1.0 / (float(sample_count) * pdf + 0.0001);

			float mipLevel = roughness == 0.0 ? 0.0 : 0.5 * log2(saSample / saTexel); 
			prefilteredColor += textureLod(u_EnvironmentMap, lightDir, mipLevel).rgb * NdotL;
            totalWeight      += NdotL;
		}
	}
    prefilteredColor = prefilteredColor / totalWeight;
    FragColor = vec4(prefilteredColor, 1.0);
}
