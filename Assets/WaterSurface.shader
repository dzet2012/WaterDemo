Shader "Water/Water-Surface"
{
    Properties
    {
		_BaseColor("Basic Color", Color) = (0, 191, 255, 1) // Diffuse Color
	    _SpecColor("Specular Color", Color) = (0.5, 0.5, 0.5, 0.5)
		
	    _FlowMap("Flow Map", 2D) = "green"{}	
		_BumpMap("Normal Map", 2D) = "bump"{}
		_NoiseMap("Noise Map", 2D) = "white"{}

		_FlowParams("Flow Params", Vector) = (0.5, 0, 0, 0) // (speed, 0, 0, 0)
		
	}
	SubShader
	{
		Tags { "Queue" = "Geometry" 
		       "RenderPipeline" = "UniversalPipeline"}
		LOD 100

		Pass
		{
			Name "ForwardLit"
			Tags{"LightMode" = "UniversalForward"}
			Blend SrcAlpha OneMinusSrcAlpha
			ZWrite On
			ZTest LEqual

		    HLSLPROGRAM
			// Material Keywords

            // Universal Pipeline Keywords
			#pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma vertex vert
            #pragma fragment frag

		    
			#include "Packages/com.unity.render-pipelines.universal/Shaders/SimpleLitInput.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/Shaders/SimpleLitForwardPass.hlsl"

            struct appdata
            {
                float4 positionOS : POSITION;
				float3 normalOS : NORMAL;
				float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 positionCS : SV_POSITION;

				float3 positionWS : TEXCOORD1; // xyz: posWS

				float4 normal : TEXCOORD3; // xyz: normal, w:viewDir.x
				float4 tangent : TEXCOORD4; // xyz: tangent, w:viewDir.y
				float4 bitangent : TEXCOORD5; // xyz: bitangent, w:viewDir.z


#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
				float4 shadowCoord : TEXCOORD7;
#endif
            };

			float4 _FlowParams;

			TEXTURE2D(_FlowMap);
			SAMPLER(sampler_FlowMap);
			float4 _FlowMap_ST;

			TEXTURE2D(_NoiseMap);
			SAMPLER(sampler_NoiseMap);
			float4 _NoiseMap_ST;

            v2f vert (appdata input)
            {
                v2f output = (v2f)0;
				output.positionCS = TransformObjectToHClip(input.positionOS.xyz);

				output.uv = TRANSFORM_TEX(input.uv, _FlowMap);
				output.positionWS = TransformObjectToWorld(input.positionOS.xyz);

				float3 viewDir = GetCameraPositionWS() - output.positionWS;

				VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

				output.normal = half4(normalInput.normalWS, viewDir.x);
				output.tangent = half4(normalInput.tangentWS, viewDir.y);
				output.bitangent = half4(normalInput.bitangentWS, viewDir.z);


#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
				output.shadowCoord = TransformWorldToShadowCoord(output.positionWS);
#endif
                return output;
            }

            half4 frag (v2f input) : SV_Target
            {

				half3 viewDir = half3(input.normal.w, input.tangent.w, input.bitangent.w);

				float2 flow = SAMPLE_TEXTURE2D(_FlowMap, sampler_FlowMap, input.uv).rg*2.0 - 1.0;
				//float cycleOffset = SAMPLE_TEXTURE2D(_NoiseMap, sampler_NoiseMap, input.uv).r;
				float cycleOffset = 1;
				float phase0 = cycleOffset * 0.5 + abs(frac(_Time.y)*2.0-1.0);
				float phase1 = cycleOffset * 0.5 + abs(frac(_Time.y-0.5)*2.0 - 1.0);

				float3 normalTS0 = SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, input.uv + flow * phase0).rgb;
				float3 normalTS1 = SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, input.uv + flow * phase1).rgb;
				float3 normalTS = lerp(normalTS0, normalTS1, length(flow));

				//half3 normalWS = TransformTangentToWorld(normalTS,
				//	half3x3(input.tangent.xyz, input.bitangent.xyz, input.normal.xyz));
				half3 normalWS = SafeNormalize(normalTS);

				viewDir = SafeNormalize(viewDir);

#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
				float4 shadowCoord = input.shadowCoord;
#elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
				float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
#else 
				float4 shadowCoord = float4(0, 0, 0, 0);
#endif

				Light mainLight = GetMainLight(shadowCoord);

				// specular lighting
				float3 reflection = reflect(mainLight.direction, normalWS);
				half4 specular = pow(max(dot(viewDir, reflection),0.0), 32) * _SpecColor * half4(mainLight.color, 1.0);
				float diffuse = max(dot(-mainLight.direction, normalWS), 0.0)+0.2;

                float4 col = _BaseColor * diffuse + specular;

				col.a = 1;
                return col;
            }
            ENDHLSL
        }
    }
}
