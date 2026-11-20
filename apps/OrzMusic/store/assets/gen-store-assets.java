/*
 * 生成商店物料 + 启动图:512 图标 / 1024x500 特色图片 / 320x180 TV banner。
 *
 * 为什么用 AWT 而不是 ImageMagick:仓库里没有 ImageMagick,而 JDK 是构建必备,
 * `java GenStoreAssets.java` 一条命令就能重出全部图,且不引入新依赖。
 *
 * 用法(仓库根):
 *   java -Djava.awt.headless=true apps/OrzMusic/store/assets/gen-store-assets.java \
 *        apps/OrzMusic/store/assets \
 *        apps/OrzMusic/app/src/main/res/drawable/banner.png
 *
 * 品牌色与 `ui/Theme.kt` 的 OrzColors 保持一致:
 *   Bg #0B0D0C / BgTop #0E1411 / Mint #39E58C / Text #F4F2EA / Muted #89918B
 */
import javax.imageio.ImageIO;
import java.awt.*;
import java.awt.geom.*;
import java.awt.image.BufferedImage;
import java.io.File;

public class GenStoreAssets {

    static final Color BG_TOP = new Color(0x0E1411);
    static final Color BG = new Color(0x0B0D0C);
    static final Color BG_BOTTOM = new Color(0x070908);
    static final Color MINT = new Color(0x39E58C);
    static final Color TEXT = new Color(0xF4F2EA);
    static final Color MUTED = new Color(0x89918B);

    // 与应用内 BrandMark 同比例:五根柱,高度 7/15/22/11/18,柱宽 = 柱间距。
    static final double[] BARS = {7 / 22.0, 15 / 22.0, 1.0, 11 / 22.0, 18 / 22.0};
    static final double BAR_W = 3 / 22.0;   // 相对最高柱
    static final double GAP_W = 3 / 22.0;

    public static void main(String[] args) throws Exception {
        File outDir = new File(args.length > 0 ? args[0] : ".");
        File bannerTarget = args.length > 1 ? new File(args[1]) : null;
        outDir.mkdirs();

        write(icon(512), new File(outDir, "icon-512.png"));
        write(featureGraphic(1024, 500), new File(outDir, "feature-graphic-1024x500.png"));
        BufferedImage banner = banner(320, 180);
        write(banner, new File(outDir, "banner-320x180.png"));
        if (bannerTarget != null) {
            bannerTarget.getParentFile().mkdirs();
            write(banner, bannerTarget);
            System.out.println("wrote " + bannerTarget);
        }
        System.out.println("wrote " + outDir + "/icon-512.png");
        System.out.println("wrote " + outDir + "/feature-graphic-1024x500.png");
        System.out.println("wrote " + outDir + "/banner-320x180.png");
    }

    static void write(BufferedImage img, File f) throws Exception {
        ImageIO.write(img, "png", f);
    }

    static BufferedImage canvas(int w, int h) {
        return new BufferedImage(w, h, BufferedImage.TYPE_INT_ARGB);
    }

    static Graphics2D g2(BufferedImage img) {
        Graphics2D g = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
        g.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING,
                RenderingHints.VALUE_TEXT_ANTIALIAS_ON);
        g.setRenderingHint(RenderingHints.KEY_STROKE_CONTROL, RenderingHints.VALUE_STROKE_PURE);
        return g;
    }

    /** 深色纵向渐变 + 左上一团薄荷微光,与应用背景同气质。 */
    static void paintBackground(Graphics2D g, int w, int h) {
        g.setPaint(new GradientPaint(0, 0, BG_TOP, 0, h, BG_BOTTOM));
        g.fillRect(0, 0, w, h);
        g.setPaint(new RadialGradientPaint(
                new Point2D.Float(w * 0.18f, h * 0.12f),
                Math.max(w, h) * 0.75f,
                new float[]{0f, 1f},
                new Color[]{new Color(0x39, 0xE5, 0x8C, 50), new Color(0x39, 0xE5, 0x8C, 0)}));
        g.fillRect(0, 0, w, h);
    }

    /** 五根圆角薄荷柱,底部对齐。返回整体宽度。 */
    static double drawMark(Graphics2D g, double left, double bottomY, double tallest) {
        double bw = BAR_W * tallest;
        double gap = GAP_W * tallest;
        double radius = bw * 0.45;
        for (int i = 0; i < BARS.length; i++) {
            double hgt = BARS[i] * tallest;
            double x = left + i * (bw + gap);
            g.setColor(MINT);
            g.fill(new RoundRectangle2D.Double(x, bottomY - hgt, bw, hgt, radius, radius));
        }
        return BARS.length * bw + (BARS.length - 1) * gap;
    }

    static double markWidth(double tallest) {
        double bw = BAR_W * tallest;
        double gap = GAP_W * tallest;
        return BARS.length * bw + (BARS.length - 1) * gap;
    }

    static Font font(int style, float size) {
        // WSL / CI 里只有 DejaVu 系;逻辑字体 SansSerif 会回落到它,不会缺字。
        Font f = new Font("DejaVu Sans", style, 12);
        if (!"DejaVu Sans".equals(f.getFamily())) f = new Font(Font.SANS_SERIF, style, 12);
        return f.deriveFont(style, size);
    }

    /** 按可用宽度收缩字号 —— 不同机器的字体度量不一样,写字板不能假设它放得下。 */
    static Font fitFont(Graphics2D g, String text, int style, float want, double maxWidth) {
        Font f = font(style, want);
        g.setFont(f);
        double w = g.getFontMetrics().stringWidth(text);
        if (w > maxWidth && w > 0) {
            f = font(style, (float) (want * maxWidth / w));
            g.setFont(f);
        }
        return f;
    }

    static BufferedImage icon(int size) {
        BufferedImage img = canvas(size, size);
        Graphics2D g = g2(img);
        paintBackground(g, size, size);

        // 全幅方图:Play 自己会裁圆角/TV 用 banner,不要预先做圆角遮罩。
        double tallest = size * 0.40;
        double left = (size - markWidth(tallest)) / 2.0;
        double bottom = (size + tallest) / 2.0;
        drawMark(g, left, bottom, tallest);

        g.dispose();
        return img;
    }

    static BufferedImage featureGraphic(int w, int h) {
        BufferedImage img = canvas(w, h);
        Graphics2D g = g2(img);
        paintBackground(g, w, h);

        double tallest = h * 0.34;
        double left = w * 0.075;
        double bottom = (h + tallest) / 2.0;
        drawMark(g, left, bottom, tallest);

        double textX = left + markWidth(tallest) + w * 0.045;
        int titleBaseline = (int) (h * 0.52);
        fitFont(g, "OrzMusic", Font.BOLD, (float) (h * 0.175), w - textX - w * 0.06);
        g.setColor(TEXT);
        g.drawString("OrzMusic", (float) textX, titleBaseline);

        fitFont(g, "CHIP AUDIO · MOD · XM · IT · S3M", Font.PLAIN, (float) (h * 0.048),
                w - textX - w * 0.06);
        g.setColor(MUTED);
        g.drawString("CHIP AUDIO · MOD · XM · IT · S3M", (float) textX, (float) (titleBaseline + h * 0.10));

        // 右侧一圈极淡的同心弧,呼应「声场」而不抢主体。
        g.setStroke(new BasicStroke(Math.max(1f, h * 0.004f)));
        double cx = w * 0.86, cy = h * 0.5;
        for (int i = 1; i <= 4; i++) {
            double r = h * 0.09 * i;
            g.setColor(new Color(0x39, 0xE5, 0x8C, 26 - i * 4));
            g.draw(new Ellipse2D.Double(cx - r, cy - r, r * 2, r * 2));
        }

        g.dispose();
        return img;
    }

    static BufferedImage banner(int w, int h) {
        BufferedImage img = canvas(w, h);
        Graphics2D g = g2(img);
        paintBackground(g, w, h);

        double tallest = h * 0.36;
        double left = w * 0.075;
        double bottom = (h + tallest) / 2.0;
        drawMark(g, left, bottom, tallest);

        double textX = left + markWidth(tallest) + w * 0.05;
        fitFont(g, "OrzMusic", Font.BOLD, (float) (h * 0.26), w - textX - w * 0.05);
        g.setColor(TEXT);
        g.drawString("OrzMusic", (float) textX, (float) (h * 0.56));
        fitFont(g, "CHIP AUDIO", Font.PLAIN, (float) (h * 0.085), w - textX - w * 0.05);
        g.setColor(MUTED);
        g.drawString("CHIP AUDIO", (float) textX, (float) (h * 0.74));

        g.dispose();
        return img;
    }
}
