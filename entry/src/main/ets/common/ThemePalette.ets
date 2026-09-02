import {
  COLOR_SCHEME_FOREST,
  COLOR_SCHEME_INK,
  COLOR_SCHEME_SUNSET
} from './Models';

export interface ThemePalette {
  pageBackground: string;
  paper: string;
  text: string;
  muted: string;
  border: string;
  input: string;
  primary: string;
  primaryText: string;
  hover: string;
  accent: string;
  danger: string;
}

const WARM_LIGHT: ThemePalette = {
  pageBackground: '#F2F2EE',
  paper: '#FFF4C7',
  text: '#28251F',
  muted: '#746D5D',
  border: '#D8CDA5',
  input: '#FFFDF4',
  primary: '#3D3A32',
  primaryText: '#FFFFFF',
  hover: '#1A6F6653',
  accent: '#9A5B3E',
  danger: '#B42318'
};

const WARM_DARK: ThemePalette = {
  pageBackground: '#171715',
  paper: '#2C2A24',
  text: '#F2EBD7',
  muted: '#AFA895',
  border: '#565044',
  input: '#39362F',
  primary: '#E8DFCA',
  primaryText: '#26231E',
  hover: '#26E8DFCA',
  accent: '#E1A078',
  danger: '#FF8A7C'
};

const INK_LIGHT: ThemePalette = {
  pageBackground: '#EEF1F4',
  paper: '#F8FAFC',
  text: '#17212B',
  muted: '#637080',
  border: '#C9D1DB',
  input: '#FFFFFF',
  primary: '#263746',
  primaryText: '#FFFFFF',
  hover: '#18263746',
  accent: '#3E647F',
  danger: '#B42318'
};

const INK_DARK: ThemePalette = {
  pageBackground: '#101419',
  paper: '#192129',
  text: '#EAF0F5',
  muted: '#9CA9B6',
  border: '#3B4A58',
  input: '#222D37',
  primary: '#D7E4EE',
  primaryText: '#15202A',
  hover: '#25D7E4EE',
  accent: '#8CB7D5',
  danger: '#FF8A7C'
};

const FOREST_LIGHT: ThemePalette = {
  pageBackground: '#EDF3EE',
  paper: '#F4F1D1',
  text: '#203126',
  muted: '#617064',
  border: '#BFCDB9',
  input: '#FBFAE9',
  primary: '#315941',
  primaryText: '#FFFFFF',
  hover: '#18315941',
  accent: '#3F7756',
  danger: '#A6382C'
};

const FOREST_DARK: ThemePalette = {
  pageBackground: '#101812',
  paper: '#1D2B20',
  text: '#E5EEDC',
  muted: '#A1B19F',
  border: '#405B46',
  input: '#26382A',
  primary: '#D9E7CE',
  primaryText: '#1B2A1E',
  hover: '#25D9E7CE',
  accent: '#85C69B',
  danger: '#FF8A7C'
};

const SUNSET_LIGHT: ThemePalette = {
  pageBackground: '#F6EEF0',
  paper: '#FFF0D8',
  text: '#3A252B',
  muted: '#80666C',
  border: '#DFC4C2',
  input: '#FFF9F3',
  primary: '#754653',
  primaryText: '#FFFFFF',
  hover: '#18754653',
  accent: '#A54D62',
  danger: '#B42318'
};

const SUNSET_DARK: ThemePalette = {
  pageBackground: '#1C1216',
  paper: '#332126',
  text: '#F6E6E2',
  muted: '#B9A0A4',
  border: '#604047',
  input: '#402A30',
  primary: '#F0D3CF',
  primaryText: '#342126',
  hover: '#25F0D3CF',
  accent: '#E493A5',
  danger: '#FF8A7C'
};

export function resolvePalette(scheme: string, dark: boolean): ThemePalette {
  if (scheme === COLOR_SCHEME_INK) {
    return dark ? INK_DARK : INK_LIGHT;
  }
  if (scheme === COLOR_SCHEME_FOREST) {
    return dark ? FOREST_DARK : FOREST_LIGHT;
  }
  if (scheme === COLOR_SCHEME_SUNSET) {
    return dark ? SUNSET_DARK : SUNSET_LIGHT;
  }
  return dark ? WARM_DARK : WARM_LIGHT;
}
