import {
  COLOR_SCHEME_FOREST,
  COLOR_SCHEME_INK,
  COLOR_SCHEME_ROSE,
  COLOR_SCHEME_WARM
} from './Models';

export interface PaperPalette {
  paper: string;
  border: string;
  text: string;
  muted: string;
  active: string;
  code: string;
  quoteBorder: string;
  link: string;
  checkbox: string;
  danger: string;
}

const WARM_LIGHT: PaperPalette = {
  paper: '#FFF9EA', border: '#E0CEA7', text: '#33291E', muted: '#8A7A63', active: '#8C7350',
  code: '#F7EDD2', quoteBorder: '#D4BE92', link: '#B06242', checkbox: '#B4A078', danger: '#B05A46'
};
const WARM_DARK: PaperPalette = {
  paper: '#211F1C', border: '#4C453D', text: '#E7E0D4', muted: '#92897B', active: '#A88E6A',
  code: '#2D2A26', quoteBorder: '#5E564B', link: '#D69678', checkbox: '#6E6455', danger: '#E66E5A'
};
const INK_LIGHT: PaperPalette = {
  paper: '#F6F7F9', border: '#D0D6DE', text: '#262C36', muted: '#767E8A', active: '#5A6C86',
  code: '#ECEFF3', quoteBorder: '#C6CED8', link: '#42689C', checkbox: '#AAB4C2', danger: '#BC5450'
};
const INK_DARK: PaperPalette = {
  paper: '#1A1C20', border: '#3C424C', text: '#DEE3EA', muted: '#8A929E', active: '#849CBC',
  code: '#26292F', quoteBorder: '#4E5662', link: '#84AAD6', checkbox: '#606A78', danger: '#E0746C'
};
const FOREST_LIGHT: PaperPalette = {
  paper: '#F3F8F1', border: '#C8DAC6', text: '#26322A', muted: '#6E8070', active: '#588260',
  code: '#E9F2E7', quoteBorder: '#C0D6C0', link: '#3C8260', checkbox: '#A8C0A8', danger: '#BC604C'
};
const FOREST_DARK: PaperPalette = {
  paper: '#1A1E1B', border: '#3A463C', text: '#DCE4DC', muted: '#869488', active: '#7CA886',
  code: '#252A26', quoteBorder: '#4A5A4C', link: '#80BE96', checkbox: '#5C6E5E', danger: '#DE7C68'
};
const ROSE_LIGHT: PaperPalette = {
  paper: '#FDF5F6', border: '#E4CDD2', text: '#36262A', muted: '#8C7278', active: '#9E6876',
  code: '#F8ECEE', quoteBorder: '#E0C6CC', link: '#B2546E', checkbox: '#D8B8C0', danger: '#BC524E'
};
const ROSE_DARK: PaperPalette = {
  paper: '#211C1E', border: '#4E4044', text: '#E8DCDF', muted: '#988489', active: '#BE8694',
  code: '#2C2628', quoteBorder: '#5C4C50', link: '#E094AA', checkbox: '#604E52', danger: '#E67264'
};

export function normalizeColorScheme(scheme: string | undefined): string {
  if (scheme === COLOR_SCHEME_INK || scheme === COLOR_SCHEME_FOREST || scheme === COLOR_SCHEME_ROSE) {
    return scheme;
  }
  return COLOR_SCHEME_WARM;
}

export function paperPalette(scheme: string | undefined, dark: boolean): PaperPalette {
  const normalized: string = normalizeColorScheme(scheme);
  if (normalized === COLOR_SCHEME_INK) {
    return dark ? INK_DARK : INK_LIGHT;
  }
  if (normalized === COLOR_SCHEME_FOREST) {
    return dark ? FOREST_DARK : FOREST_LIGHT;
  }
  if (normalized === COLOR_SCHEME_ROSE) {
    return dark ? ROSE_DARK : ROSE_LIGHT;
  }
  return dark ? WARM_DARK : WARM_LIGHT;
}
