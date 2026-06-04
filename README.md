# jodidaniel.com

## Visual Design

### Inspiration
The design is inspired by [lisabari.com](https://lisabari.com/), featuring:
- Modern gradient background (blue tones)
- Clean typography with Raleway and Source Sans Pro fonts
- Subtle fade-in-while-sliding-up animations on page load
- White card containers with shadow effects

### Color Palette
| Color | Hex | Usage |
|-------|-----|-------|
| Dark Navy | `#1a3a5c` | Headings, primary text |
| Medium Blue | `#2d5a7b` | Links, highlights |
| Teal Accent | `#5dd9e8` | Borders, hover states |
| Light Gray | `#f8fafc` | Card backgrounds |
| White | `#ffffff` | Main containers |

### Typography
- **Headers:** Raleway (600-700 weight, uppercase with letter-spacing)
- **Body:** Source Sans Pro (300 weight for light, readable text)

### Animations
Elements use the `animate-in` class with staggered delays (`delay-1` through `delay-7`):
- Animation: fade in while sliding up 30px
- Duration: 0.8s ease-out
- Delays range from 0.1s to 1.2s for cascading effect

### Responsive Breakpoints
- **> 900px:** 2-column expertise grid
- **≤ 900px:** Single-column expertise grid
- **≤ 768px:** Full mobile layout (centered content, smaller fonts)

## Content Sections

The page is `index.html` (`layout: home` → `_layouts/home.html`). `mockup.html`
is the design reference for the layout and `assets/css/jodidaniel.css`. All
copy is editable via `/admin` (Decap CMS) — see [AGENTS.md](AGENTS.md) for the
full content model, the `site_live` go-live gate, and OAuth details.

1. **Header** - Name and tagline (`_data/header.yml`)
2. **About/Intro** - Profile photo, bio paragraphs, in-page nav (`_data/about.yml`)
3. **Expertise** - Practice-area cards (`_expertise/` collection, ordered by `weight`)
4. **Experience** - Timeline of professional history (`_experience/` collection)
5. **Accomplishments** - Key career achievements (`_accomplishments/` collection)
6. **Media** - Publications, podcasts, speaking, press, grouped by `category` (`_media/` collection)
7. **Education** - J.D., M.P.H., and B.A. credentials (`_education/` collection)
8. **Contact** - Links to WSGR profile and LinkedIn (`_data/contact.yml`)

Site-wide settings — including the `site_live` gate (coming-soon vs. full bio),
coming-soon/footer copyright, and section headings — live in
`_data/settings.yml`.
