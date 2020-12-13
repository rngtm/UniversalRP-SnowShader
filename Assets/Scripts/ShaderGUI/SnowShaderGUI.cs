using System;
using UnityEngine;

namespace UnityEditor.Rendering.Universal.ShaderGUI
{
    // Snow.shader マテリアル設定用 ShaderGUI
    internal class SnowShaderGUI : BaseShaderGUI
    {
        // Properties
        private LitGUI.LitProperties litProperties;

        protected MaterialProperty surfaceTypeProp { get; set; }
        
        public static readonly GUIContent SnowFoldOptions =
            new GUIContent("Snow Options", "Controls how Universal RP renders the Material on a screen.");
        
        #region Variables
        protected MaterialProperty snowAmountProp;
        protected MaterialProperty snowSpecularGlossProp;
        protected MaterialProperty noisePositionScaleProp;
        protected MaterialProperty noiseInclinationScaleProp;
        protected MaterialProperty snowDiffuseNormalDistortion;
        protected MaterialProperty snowSpecularNormalDistortion;
        protected MaterialProperty snowDirectionProp;
        protected MaterialProperty snowDotNormalRemapProp;
        protected MaterialProperty diffuseColorProp;
        protected MaterialProperty specularColorProp;
        #endregion
        
        // collect properties from the material properties
        public override void FindProperties(MaterialProperty[] properties)
        {
            base.FindProperties(properties);
            litProperties = new LitGUI.LitProperties(properties);
            
            snowAmountProp = FindProperty("_SnowAmount", properties);
            snowSpecularGlossProp = FindProperty("_SnowSpecularGloss", properties);
            noisePositionScaleProp = FindProperty("_NoisePositionScale", properties);
            noiseInclinationScaleProp = FindProperty("_NoiseInclinationScale", properties);
            snowDiffuseNormalDistortion = FindProperty("_DiffuseNormalNoiseScale", properties);
            snowSpecularNormalDistortion = FindProperty("_SpecularNormalNoiseScale", properties);
            snowDirectionProp = FindProperty("_SnowDirection", properties);
            snowDotNormalRemapProp = FindProperty("_SnowDotNormalRemap", properties);
            diffuseColorProp = FindProperty("_DiffuseColor", properties);
            specularColorProp = FindProperty("_SpecularColor", properties);
        }

        // material changed check
        public override void MaterialChanged(Material material)
        {
            if (material == null)
                throw new ArgumentNullException("material");

            SetMaterialKeywords(material, LitGUI.SetMaterialKeywords);
        }

        // material main surface options
        public override void DrawSurfaceOptions(Material material)
        {
            if (material == null)
                throw new ArgumentNullException("material");

            // Use default labelWidth
            EditorGUIUtility.labelWidth = 0f;

            // Detect any changes to the material
            EditorGUI.BeginChangeCheck();
            if (litProperties.workflowMode != null)
            {
                DoPopup(LitGUI.Styles.workflowModeText, litProperties.workflowMode, Enum.GetNames(typeof(LitGUI.WorkflowMode)));
            }
            if (EditorGUI.EndChangeCheck())
            {
                foreach (var obj in blendModeProp.targets)
                    MaterialChanged((Material)obj);
            }
            base.DrawSurfaceOptions(material);
        }

        // material main surface inputs
        public override void DrawSurfaceInputs(Material material)
        {
            base.DrawSurfaceInputs(material);

            LitGUI.Inputs(litProperties, materialEditor, material);
            DrawEmissionProperties(material, true);
            DrawTileOffset(materialEditor, baseMapProp);
            EditorGUILayout.Separator();
            
            // snow parameters
            GUILayout.Label("[Snow Parameter]");
            using (new EditorGUI.IndentLevelScope())
            {
                DoSnowAmountValue(snowAmountProp, material);
                
                materialEditor.ColorProperty(diffuseColorProp, "Diffuse Color");
                materialEditor.ColorProperty(specularColorProp, "Specular Color");
                
                materialEditor.FloatProperty(snowSpecularGlossProp, "SnowSpecularGloss");
                materialEditor.FloatProperty(noisePositionScaleProp, "NoisePositionScale");
                materialEditor.FloatProperty(noiseInclinationScaleProp, "Noise Scale (Inclination)");
                materialEditor.FloatProperty(snowDiffuseNormalDistortion, "Diffuse Normal Scale"); 
                materialEditor.FloatProperty(snowSpecularNormalDistortion, "Specular Normal Scale");
                materialEditor.VectorProperty(snowDirectionProp, "Snow Direction");
                materialEditor.VectorProperty(snowDotNormalRemapProp, "dot(N, S) remap : [x,y] -> [z,w]");
            }
        }
        
        public static void DoSnowAmountValue(MaterialProperty prop, Material material)
        {
            EditorGUI.BeginChangeCheck();
            var snowAmount = EditorGUILayout.Slider("SnowAmount", prop.floatValue, 0f, 1f);
            if (EditorGUI.EndChangeCheck())
                prop.floatValue = snowAmount;
        }

        // material main advanced options
        public override void DrawAdvancedOptions(Material material)
        {
            if (litProperties.reflections != null && litProperties.highlights != null)
            {
                EditorGUI.BeginChangeCheck();
                materialEditor.ShaderProperty(litProperties.highlights, LitGUI.Styles.highlightsText);
                materialEditor.ShaderProperty(litProperties.reflections, LitGUI.Styles.reflectionsText);
                if(EditorGUI.EndChangeCheck())
                {
                    MaterialChanged(material);
                }
            }

            base.DrawAdvancedOptions(material);
        }

        public override void AssignNewShaderToMaterial(Material material, Shader oldShader, Shader newShader)
        {
            if (material == null)
                throw new ArgumentNullException("material");

            // _Emission property is lost after assigning Standard shader to the material
            // thus transfer it before assigning the new shader
            if (material.HasProperty("_Emission"))
            {
                material.SetColor("_EmissionColor", material.GetColor("_Emission"));
            }

            base.AssignNewShaderToMaterial(material, oldShader, newShader);

            if (oldShader == null || !oldShader.name.Contains("Legacy Shaders/"))
            {
                SetupMaterialBlendMode(material);
                return;
            }

            SurfaceType surfaceType = SurfaceType.Opaque;
            BlendMode blendMode = BlendMode.Alpha;
            if (oldShader.name.Contains("/Transparent/Cutout/"))
            {
                surfaceType = SurfaceType.Opaque;
                material.SetFloat("_AlphaClip", 1);
            }
            else if (oldShader.name.Contains("/Transparent/"))
            {
                // NOTE: legacy shaders did not provide physically based transparency
                // therefore Fade mode
                surfaceType = SurfaceType.Transparent;
                blendMode = BlendMode.Alpha;
            }
            material.SetFloat("_Surface", (float)surfaceType);
            material.SetFloat("_Blend", (float)blendMode);

            if (oldShader.name.Equals("Standard (Specular setup)"))
            {
                material.SetFloat("_WorkflowMode", (float)LitGUI.WorkflowMode.Specular);
                Texture texture = material.GetTexture("_SpecGlossMap");
                if (texture != null)
                    material.SetTexture("_MetallicSpecGlossMap", texture);
            }
            else
            {
                material.SetFloat("_WorkflowMode", (float)LitGUI.WorkflowMode.Metallic);
                Texture texture = material.GetTexture("_MetallicGlossMap");
                if (texture != null)
                    material.SetTexture("_MetallicSpecGlossMap", texture);
            }

            MaterialChanged(material);
        }
    }
}
