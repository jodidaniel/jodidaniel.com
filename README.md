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

1. **Header** - Name and tagline with gradient background
2. **About/Intro** - Profile placeholder, bio text, and navigation links
3. **Expertise** - 6 cards covering practice areas (Digital Health & AI, Health Data Privacy, FDA & Regulatory Strategy, Telehealth, Health IT Policy, Strategic Advisory)
4. **Experience** - Timeline of professional history
5. **Accomplishments** - Key career achievements (HIPAA architect, etc.)
6. **Education** - J.D., M.P.H., and B.A. credentials
7. **Contact** - Links to WSGR profile and LinkedIn
