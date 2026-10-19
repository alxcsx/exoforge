using UnityEditor;
using UnityEngine;
using UnityEngine.UIElements;

namespace Exoforge.Unity.Editor
{
    /// <summary>
    /// Modern design system, web-like tokens, and Exoforge brand purple styling for UI Toolkit editor windows.
    /// Standardized for high contrast and harmony in both Unity Pro (Dark) and Personal (Light) skins.
    /// </summary>
    public static class ExoforgeUIStyle
    {
        public static bool IsDark => EditorGUIUtility.isProSkin;

        // --- Exoforge Brand Purple Palette ---
        public static Color BrandPurple => new Color(0.486f, 0.227f, 0.929f, 1f);       // #7c3aed (Exoforge Primary)
        public static Color BrandPurpleDark => new Color(0.145f, 0.071f, 0.298f, 1f);   // #25124c (Deep Header Masthead)
        public static Color BrandPurpleHeader => new Color(0.176f, 0.086f, 0.361f, 1f); // #2d165c
        public static Color BrandPurpleDeep => new Color(0.102f, 0.047f, 0.208f, 1f);   // #1a0c35
        public static Color BrandPurpleLight => new Color(0.682f, 0.482f, 1.0f, 1f);    // #ae7bff
        public static Color BrandPurpleBorder => new Color(0.38f, 0.20f, 0.68f, 0.65f);
        public static Color BrandPurpleGlow => IsDark
            ? new Color(0.486f, 0.227f, 0.929f, 0.22f)
            : new Color(0.486f, 0.227f, 0.929f, 0.12f);
        public static Color BrandPurpleActive => IsDark ? BrandPurpleLight : BrandPurple;

        // --- Surface Backgrounds (Body / Canvas) ---
        public static Color BgWindow => IsDark
            ? new Color(0.130f, 0.130f, 0.145f, 1f)  // #212125 smooth dark charcoal
            : new Color(0.950f, 0.955f, 0.965f, 1f); // #f2f4f6 soft off-white canvas

        public static Color BgPanel => IsDark
            ? new Color(0.100f, 0.100f, 0.115f, 1f)  // #1a1a1d recessed container / sidebar
            : new Color(0.910f, 0.918f, 0.935f, 1f); // #e8eaee soft sidebar tone

        public static Color BgCard => IsDark
            ? new Color(0.165f, 0.165f, 0.185f, 1f)  // #2a2a2f elevated card
            : new Color(1.0f, 1.0f, 1.0f, 1f);       // #ffffff pure white card

        public static Color BgCardHover => IsDark
            ? new Color(0.200f, 0.200f, 0.230f, 1f)
            : new Color(0.965f, 0.970f, 0.985f, 1f);

        public static Color BgCardSelected => IsDark
            ? new Color(0.210f, 0.160f, 0.340f, 1f)
            : new Color(0.930f, 0.900f, 0.990f, 1f);

        public static Color BgInput => IsDark
            ? new Color(0.090f, 0.090f, 0.100f, 1f)
            : new Color(1.0f, 1.0f, 1.0f, 1f);

        // --- Header Tokens (Always branded purple in both skins) ---
        public static Color BgHeaderDark => IsDark ? BrandPurpleDark : new Color(0.130f, 0.060f, 0.260f, 1f);
        public static Color BgHeader => IsDark ? BrandPurpleHeader : new Color(0.170f, 0.085f, 0.340f, 1f);
        public static Color TextHeaderPrimary => Color.white;
        public static Color TextHeaderSecondary => new Color(0.86f, 0.85f, 0.93f, 1f);
        public static Color TextHeaderMuted => new Color(0.72f, 0.70f, 0.82f, 1f);
        public static Color BgHeaderCapsule => new Color(0f, 0f, 0f, 0.35f);
        public static Color BorderHeaderCapsule => new Color(1f, 1f, 1f, 0.14f);
        public static Color BgHeaderBtn => new Color(1f, 1f, 1f, 0.12f);
        public static Color BorderHeaderBtn => new Color(1f, 1f, 1f, 0.20f);
        public static Color DividerHeader => new Color(1f, 1f, 1f, 0.18f);

        // --- Buttons (General Body) ---
        public static Color ButtonBg => IsDark
            ? new Color(0.20f, 0.20f, 0.23f, 1f)
            : new Color(0.98f, 0.98f, 0.99f, 1f);
        public static Color ButtonBorder => IsDark
            ? new Color(0.28f, 0.28f, 0.32f, 1f)
            : new Color(0.78f, 0.79f, 0.83f, 1f);
        public static Color ButtonText => TextPrimary;

        // --- Borders ---
        public static Color BorderSubtle => IsDark
            ? new Color(0.25f, 0.25f, 0.28f, 0.8f)
            : new Color(0.82f, 0.83f, 0.86f, 1f);
        public static Color BorderCardSelected => BrandPurple;
        public static Color BorderLight => IsDark
            ? new Color(0.32f, 0.32f, 0.36f, 0.8f)
            : new Color(0.76f, 0.77f, 0.80f, 1f);

        // --- Typography ---
        public static Color TextPrimary => IsDark
            ? new Color(0.95f, 0.95f, 0.96f, 1f)  // #f2f2f5
            : new Color(0.12f, 0.12f, 0.14f, 1f); // #1f1f24
        public static Color TextSecondary => IsDark
            ? new Color(0.72f, 0.72f, 0.77f, 1f)  // #b8b8c4
            : new Color(0.36f, 0.37f, 0.42f, 1f); // #5c5e6b
        public static Color TextMuted => IsDark
            ? new Color(0.52f, 0.52f, 0.57f, 1f)  // #858591
            : new Color(0.55f, 0.56f, 0.61f, 1f); // #8c8f9c

        // --- Status Accents ---
        public static Color AccentGreen => IsDark
            ? new Color(0.22f, 0.82f, 0.46f, 1f)
            : new Color(0.10f, 0.62f, 0.32f, 1f);
        public static Color AccentGreenBg => IsDark
            ? new Color(0.10f, 0.26f, 0.16f, 0.8f)
            : new Color(0.86f, 0.96f, 0.90f, 1f);

        public static Color AccentBlue => IsDark
            ? new Color(0.38f, 0.70f, 1.0f, 1f)
            : new Color(0.15f, 0.48f, 0.88f, 1f);
        public static Color AccentBlueBg => IsDark
            ? new Color(0.14f, 0.26f, 0.45f, 0.8f)
            : new Color(0.88f, 0.93f, 1.0f, 1f);

        public static Color AccentOrange => IsDark
            ? new Color(1.0f, 0.65f, 0.20f, 1f)
            : new Color(0.85f, 0.45f, 0.05f, 1f);
        public static Color AccentOrangeBg => IsDark
            ? new Color(0.35f, 0.20f, 0.08f, 0.8f)
            : new Color(1.0f, 0.92f, 0.82f, 1f);

        public static Color AccentPurple => BrandPurple;
        public static Color AccentPurpleBg => IsDark
            ? new Color(0.28f, 0.14f, 0.48f, 0.8f)
            : new Color(0.93f, 0.88f, 1.0f, 1f);

        public static Color AccentRed => IsDark
            ? new Color(0.95f, 0.38f, 0.38f, 1f)
            : new Color(0.82f, 0.20f, 0.20f, 1f);
        public static Color AccentRedBg => IsDark
            ? new Color(0.35f, 0.12f, 0.12f, 0.8f)
            : new Color(1.0f, 0.88f, 0.88f, 1f);

        public static Color AccentGray => IsDark
            ? new Color(0.58f, 0.58f, 0.63f, 1f)
            : new Color(0.48f, 0.48f, 0.52f, 1f);
        public static Color AccentGrayBg => IsDark
            ? new Color(0.20f, 0.20f, 0.23f, 0.8f)
            : new Color(0.90f, 0.90f, 0.93f, 1f);

        // --- IMGUI Tones ---
        public static Color ImguiHeroBoxBg => IsDark
            ? new Color(0.22f, 0.14f, 0.38f, 0.6f)
            : new Color(0.93f, 0.89f, 0.99f, 1f);
        public static Color ImguiCardBg => IsDark
            ? new Color(0.165f, 0.165f, 0.185f, 1f)
            : new Color(1.0f, 1.0f, 1.0f, 1f);

        public static void ApplyCard(VisualElement card, bool isSelected = false)
        {
            card.style.backgroundColor = isSelected ? BgCardSelected : BgCard;
            card.style.borderTopWidth = 1;
            card.style.borderBottomWidth = 1;
            card.style.borderLeftWidth = 1;
            card.style.borderRightWidth = 1;
            card.style.borderTopColor = isSelected ? BorderCardSelected : BorderSubtle;
            card.style.borderBottomColor = isSelected ? BorderCardSelected : BorderSubtle;
            card.style.borderLeftColor = isSelected ? BorderCardSelected : BorderSubtle;
            card.style.borderRightColor = isSelected ? BorderCardSelected : BorderSubtle;
            card.style.borderTopLeftRadius = 8;
            card.style.borderTopRightRadius = 8;
            card.style.borderBottomLeftRadius = 8;
            card.style.borderBottomRightRadius = 8;
            card.style.paddingTop = 10;
            card.style.paddingBottom = 10;
            card.style.paddingLeft = 12;
            card.style.paddingRight = 12;
            card.style.marginBottom = 8;

            if (!isSelected)
            {
                card.RegisterCallback<MouseEnterEvent>(_ => { card.style.backgroundColor = BgCardHover; });
                card.RegisterCallback<MouseLeaveEvent>(_ => { card.style.backgroundColor = BgCard; });
            }
        }

        public static VisualElement CreatePill(string text, Color textColor, Color bgColor, int fontSize = 10)
        {
            var pill = new VisualElement();
            pill.style.flexDirection = FlexDirection.Row;
            pill.style.alignItems = Align.Center;
            pill.style.backgroundColor = bgColor;
            pill.style.borderTopLeftRadius = 12;
            pill.style.borderTopRightRadius = 12;
            pill.style.borderBottomLeftRadius = 12;
            pill.style.borderBottomRightRadius = 12;
            pill.style.paddingLeft = 8;
            pill.style.paddingRight = 8;
            pill.style.paddingTop = 3;
            pill.style.paddingBottom = 3;
            pill.style.marginLeft = 3;
            pill.style.marginRight = 3;

            var label = new Label(text);
            label.style.color = textColor;
            label.style.fontSize = fontSize;
            label.style.unityFontStyleAndWeight = FontStyle.Bold;
            pill.Add(label);

            return pill;
        }

        public static VisualElement CreateStatusDot(Color dotColor, float size = 8f)
        {
            var dot = new VisualElement();
            dot.style.width = size;
            dot.style.height = size;
            dot.style.borderTopLeftRadius = size / 2f;
            dot.style.borderTopRightRadius = size / 2f;
            dot.style.borderBottomLeftRadius = size / 2f;
            dot.style.borderBottomRightRadius = size / 2f;
            dot.style.backgroundColor = dotColor;
            dot.style.marginRight = 6;
            dot.style.alignSelf = Align.Center;
            return dot;
        }

        public static Button CreateModernButton(string text, System.Action onClick, Color? bg = null, Color? textCol = null, float height = 26, bool isHeader = false)
        {
            var btn = new Button(onClick) { text = text };
            btn.style.height = height;
            btn.style.borderTopLeftRadius = 6;
            btn.style.borderTopRightRadius = 6;
            btn.style.borderBottomLeftRadius = 6;
            btn.style.borderBottomRightRadius = 6;
            btn.style.borderTopWidth = 1;
            btn.style.borderBottomWidth = 1;
            btn.style.borderLeftWidth = 1;
            btn.style.borderRightWidth = 1;

            Color defaultBg = isHeader ? BgHeaderBtn : ButtonBg;
            Color defaultBorder = isHeader ? BorderHeaderBtn : ButtonBorder;
            Color defaultText = isHeader ? TextHeaderPrimary : ButtonText;

            btn.style.borderTopColor = defaultBorder;
            btn.style.borderBottomColor = defaultBorder;
            btn.style.borderLeftColor = defaultBorder;
            btn.style.borderRightColor = defaultBorder;
            btn.style.backgroundColor = bg ?? defaultBg;
            btn.style.color = textCol ?? defaultText;

            btn.style.paddingLeft = 12;
            btn.style.paddingRight = 12;
            btn.style.marginLeft = 3;
            btn.style.marginRight = 3;
            btn.style.unityFontStyleAndWeight = FontStyle.Bold;
            btn.style.fontSize = 11;

            return btn;
        }

        public static Button CreateEnvSelector(string envName, System.Action onClick, out Label envLabel)
        {
            var btn = new Button(onClick);
            btn.style.height = 24;
            btn.style.flexDirection = FlexDirection.Row;
            btn.style.alignItems = Align.Center;
            btn.style.backgroundColor = BgHeaderBtn;
            btn.style.borderTopLeftRadius = 12;
            btn.style.borderTopRightRadius = 12;
            btn.style.borderBottomLeftRadius = 12;
            btn.style.borderBottomRightRadius = 12;
            btn.style.borderTopWidth = 1;
            btn.style.borderBottomWidth = 1;
            btn.style.borderLeftWidth = 1;
            btn.style.borderRightWidth = 1;
            btn.style.borderTopColor = BorderHeaderBtn;
            btn.style.borderBottomColor = BorderHeaderBtn;
            btn.style.borderLeftColor = BorderHeaderBtn;
            btn.style.borderRightColor = BorderHeaderBtn;
            btn.style.paddingLeft = 8;
            btn.style.paddingRight = 8;
            btn.style.paddingTop = 0;
            btn.style.paddingBottom = 0;
            btn.style.marginLeft = 4;
            btn.style.marginRight = 4;

            var dot = CreateStatusDot(new Color(0.4f, 0.85f, 0.55f, 1f), 6f);
            dot.style.marginRight = 5;
            btn.Add(dot);

            envLabel = new Label(envName);
            envLabel.style.fontSize = 11;
            envLabel.style.color = TextHeaderPrimary;
            envLabel.style.unityFontStyleAndWeight = FontStyle.Bold;
            envLabel.style.marginRight = 4;
            btn.Add(envLabel);

            var chevron = new Label("▾");
            chevron.style.fontSize = 10;
            chevron.style.color = TextHeaderSecondary;
            btn.Add(chevron);

            return btn;
        }

        public static VisualElement CreateDivider(float marginY = 6f)
        {
            var div = new VisualElement();
            div.style.height = 1;
            div.style.backgroundColor = BorderSubtle;
            div.style.marginTop = marginY;
            div.style.marginBottom = marginY;
            return div;
        }
    }
}
