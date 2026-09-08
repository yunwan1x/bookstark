/*! pako 2.0.3 https://github.com/nodeca/pako @license (MIT AND Zlib) */
function oe(e) {
  let i = e.length;
  for (; --i >= 0; )
    e[i] = 0;
}
const Li = 0, ti = 1, Ui = 2, Ci = 3, Fi = 258, dt = 29, Ae = 256, we = Ae + 1 + dt, fe = 30, st = 19, ii = 2 * we + 1, Q = 15, Ge = 16, Mi = 7, ct = 256, ni = 16, ai = 17, li = 18, ft = (
  /* extra bits for each length code */
  new Uint8Array([0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0])
), Oe = (
  /* extra bits for each distance code */
  new Uint8Array([0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13])
), $i = (
  /* extra bits for each bit length code */
  new Uint8Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 3, 7])
), ri = new Uint8Array([16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]), Hi = 512, B = new Array((we + 2) * 2);
oe(B);
const ce = new Array(fe * 2);
oe(ce);
const ge = new Array(Hi);
oe(ge);
const pe = new Array(Fi - Ci + 1);
oe(pe);
const ut = new Array(dt);
oe(ut);
const Fe = new Array(fe);
oe(Fe);
function je(e, i, t, a, n) {
  this.static_tree = e, this.extra_bits = i, this.extra_base = t, this.elems = a, this.max_length = n, this.has_stree = e && e.length;
}
let fi, oi, _i;
function We(e, i) {
  this.dyn_tree = e, this.max_code = 0, this.stat_desc = i;
}
const hi = (e) => e < 256 ? ge[e] : ge[256 + (e >>> 7)], xe = (e, i) => {
  e.pending_buf[e.pending++] = i & 255, e.pending_buf[e.pending++] = i >>> 8 & 255;
}, O = (e, i, t) => {
  e.bi_valid > Ge - t ? (e.bi_buf |= i << e.bi_valid & 65535, xe(e, e.bi_buf), e.bi_buf = i >> Ge - e.bi_valid, e.bi_valid += t - Ge) : (e.bi_buf |= i << e.bi_valid & 65535, e.bi_valid += t);
}, M = (e, i, t) => {
  O(
    e,
    t[i * 2],
    t[i * 2 + 1]
    /*.Len*/
  );
}, di = (e, i) => {
  let t = 0;
  do
    t |= e & 1, e >>>= 1, t <<= 1;
  while (--i > 0);
  return t >>> 1;
}, Bi = (e) => {
  e.bi_valid === 16 ? (xe(e, e.bi_buf), e.bi_buf = 0, e.bi_valid = 0) : e.bi_valid >= 8 && (e.pending_buf[e.pending++] = e.bi_buf & 255, e.bi_buf >>= 8, e.bi_valid -= 8);
}, Ki = (e, i) => {
  const t = i.dyn_tree, a = i.max_code, n = i.stat_desc.static_tree, l = i.stat_desc.has_stree, o = i.stat_desc.extra_bits, f = i.stat_desc.extra_base, c = i.stat_desc.max_length;
  let r, _, E, s, h, u, R = 0;
  for (s = 0; s <= Q; s++)
    e.bl_count[s] = 0;
  for (t[e.heap[e.heap_max] * 2 + 1] = 0, r = e.heap_max + 1; r < ii; r++)
    _ = e.heap[r], s = t[t[_ * 2 + 1] * 2 + 1] + 1, s > c && (s = c, R++), t[_ * 2 + 1] = s, !(_ > a) && (e.bl_count[s]++, h = 0, _ >= f && (h = o[_ - f]), u = t[_ * 2], e.opt_len += u * (s + h), l && (e.static_len += u * (n[_ * 2 + 1] + h)));
  if (R !== 0) {
    do {
      for (s = c - 1; e.bl_count[s] === 0; )
        s--;
      e.bl_count[s]--, e.bl_count[s + 1] += 2, e.bl_count[c]--, R -= 2;
    } while (R > 0);
    for (s = c; s !== 0; s--)
      for (_ = e.bl_count[s]; _ !== 0; )
        E = e.heap[--r], !(E > a) && (t[E * 2 + 1] !== s && (e.opt_len += (s - t[E * 2 + 1]) * t[E * 2], t[E * 2 + 1] = s), _--);
  }
}, si = (e, i, t) => {
  const a = new Array(Q + 1);
  let n = 0, l, o;
  for (l = 1; l <= Q; l++)
    a[l] = n = n + t[l - 1] << 1;
  for (o = 0; o <= i; o++) {
    let f = e[o * 2 + 1];
    f !== 0 && (e[o * 2] = di(a[f]++, f));
  }
}, Xi = () => {
  let e, i, t, a, n;
  const l = new Array(Q + 1);
  for (t = 0, a = 0; a < dt - 1; a++)
    for (ut[a] = t, e = 0; e < 1 << ft[a]; e++)
      pe[t++] = a;
  for (pe[t - 1] = a, n = 0, a = 0; a < 16; a++)
    for (Fe[a] = n, e = 0; e < 1 << Oe[a]; e++)
      ge[n++] = a;
  for (n >>= 7; a < fe; a++)
    for (Fe[a] = n << 7, e = 0; e < 1 << Oe[a] - 7; e++)
      ge[256 + n++] = a;
  for (i = 0; i <= Q; i++)
    l[i] = 0;
  for (e = 0; e <= 143; )
    B[e * 2 + 1] = 8, e++, l[8]++;
  for (; e <= 255; )
    B[e * 2 + 1] = 9, e++, l[9]++;
  for (; e <= 279; )
    B[e * 2 + 1] = 7, e++, l[7]++;
  for (; e <= 287; )
    B[e * 2 + 1] = 8, e++, l[8]++;
  for (si(B, we + 1, l), e = 0; e < fe; e++)
    ce[e * 2 + 1] = 5, ce[e * 2] = di(e, 5);
  fi = new je(B, ft, Ae + 1, we, Q), oi = new je(ce, Oe, 0, fe, Q), _i = new je(new Array(0), $i, 0, st, Mi);
}, ci = (e) => {
  let i;
  for (i = 0; i < we; i++)
    e.dyn_ltree[i * 2] = 0;
  for (i = 0; i < fe; i++)
    e.dyn_dtree[i * 2] = 0;
  for (i = 0; i < st; i++)
    e.bl_tree[i * 2] = 0;
  e.dyn_ltree[ct * 2] = 1, e.opt_len = e.static_len = 0, e.last_lit = e.matches = 0;
}, ui = (e) => {
  e.bi_valid > 8 ? xe(e, e.bi_buf) : e.bi_valid > 0 && (e.pending_buf[e.pending++] = e.bi_buf), e.bi_buf = 0, e.bi_valid = 0;
}, Pi = (e, i, t, a) => {
  ui(e), xe(e, t), xe(e, ~t), e.pending_buf.set(e.window.subarray(i, i + t), e.pending), e.pending += t;
}, gt = (e, i, t, a) => {
  const n = i * 2, l = t * 2;
  return e[n] < e[l] || e[n] === e[l] && a[i] <= a[t];
}, Ve = (e, i, t) => {
  const a = e.heap[t];
  let n = t << 1;
  for (; n <= e.heap_len && (n < e.heap_len && gt(i, e.heap[n + 1], e.heap[n], e.depth) && n++, !gt(i, a, e.heap[n], e.depth)); )
    e.heap[t] = e.heap[n], t = n, n <<= 1;
  e.heap[t] = a;
}, pt = (e, i, t) => {
  let a, n, l = 0, o, f;
  if (e.last_lit !== 0)
    do
      a = e.pending_buf[e.d_buf + l * 2] << 8 | e.pending_buf[e.d_buf + l * 2 + 1], n = e.pending_buf[e.l_buf + l], l++, a === 0 ? M(e, n, i) : (o = pe[n], M(e, o + Ae + 1, i), f = ft[o], f !== 0 && (n -= ut[o], O(e, n, f)), a--, o = hi(a), M(e, o, t), f = Oe[o], f !== 0 && (a -= Fe[o], O(e, a, f)));
    while (l < e.last_lit);
  M(e, ct, i);
}, ot = (e, i) => {
  const t = i.dyn_tree, a = i.stat_desc.static_tree, n = i.stat_desc.has_stree, l = i.stat_desc.elems;
  let o, f, c = -1, r;
  for (e.heap_len = 0, e.heap_max = ii, o = 0; o < l; o++)
    t[o * 2] !== 0 ? (e.heap[++e.heap_len] = c = o, e.depth[o] = 0) : t[o * 2 + 1] = 0;
  for (; e.heap_len < 2; )
    r = e.heap[++e.heap_len] = c < 2 ? ++c : 0, t[r * 2] = 1, e.depth[r] = 0, e.opt_len--, n && (e.static_len -= a[r * 2 + 1]);
  for (i.max_code = c, o = e.heap_len >> 1; o >= 1; o--)
    Ve(e, t, o);
  r = l;
  do
    o = e.heap[
      1
      /*SMALLEST*/
    ], e.heap[
      1
      /*SMALLEST*/
    ] = e.heap[e.heap_len--], Ve(
      e,
      t,
      1
      /*SMALLEST*/
    ), f = e.heap[
      1
      /*SMALLEST*/
    ], e.heap[--e.heap_max] = o, e.heap[--e.heap_max] = f, t[r * 2] = t[o * 2] + t[f * 2], e.depth[r] = (e.depth[o] >= e.depth[f] ? e.depth[o] : e.depth[f]) + 1, t[o * 2 + 1] = t[f * 2 + 1] = r, e.heap[
      1
      /*SMALLEST*/
    ] = r++, Ve(
      e,
      t,
      1
      /*SMALLEST*/
    );
  while (e.heap_len >= 2);
  e.heap[--e.heap_max] = e.heap[
    1
    /*SMALLEST*/
  ], Ki(e, i), si(t, c, e.bl_count);
}, xt = (e, i, t) => {
  let a, n = -1, l, o = i[1], f = 0, c = 7, r = 4;
  for (o === 0 && (c = 138, r = 3), i[(t + 1) * 2 + 1] = 65535, a = 0; a <= t; a++)
    l = o, o = i[(a + 1) * 2 + 1], !(++f < c && l === o) && (f < r ? e.bl_tree[l * 2] += f : l !== 0 ? (l !== n && e.bl_tree[l * 2]++, e.bl_tree[ni * 2]++) : f <= 10 ? e.bl_tree[ai * 2]++ : e.bl_tree[li * 2]++, f = 0, n = l, o === 0 ? (c = 138, r = 3) : l === o ? (c = 6, r = 3) : (c = 7, r = 4));
}, kt = (e, i, t) => {
  let a, n = -1, l, o = i[1], f = 0, c = 7, r = 4;
  for (o === 0 && (c = 138, r = 3), a = 0; a <= t; a++)
    if (l = o, o = i[(a + 1) * 2 + 1], !(++f < c && l === o)) {
      if (f < r)
        do
          M(e, l, e.bl_tree);
        while (--f !== 0);
      else l !== 0 ? (l !== n && (M(e, l, e.bl_tree), f--), M(e, ni, e.bl_tree), O(e, f - 3, 2)) : f <= 10 ? (M(e, ai, e.bl_tree), O(e, f - 3, 3)) : (M(e, li, e.bl_tree), O(e, f - 11, 7));
      f = 0, n = l, o === 0 ? (c = 138, r = 3) : l === o ? (c = 6, r = 3) : (c = 7, r = 4);
    }
}, Yi = (e) => {
  let i;
  for (xt(e, e.dyn_ltree, e.l_desc.max_code), xt(e, e.dyn_dtree, e.d_desc.max_code), ot(e, e.bl_desc), i = st - 1; i >= 3 && e.bl_tree[ri[i] * 2 + 1] === 0; i--)
    ;
  return e.opt_len += 3 * (i + 1) + 5 + 5 + 4, i;
}, Gi = (e, i, t, a) => {
  let n;
  for (O(e, i - 257, 5), O(e, t - 1, 5), O(e, a - 4, 4), n = 0; n < a; n++)
    O(e, e.bl_tree[ri[n] * 2 + 1], 3);
  kt(e, e.dyn_ltree, i - 1), kt(e, e.dyn_dtree, t - 1);
}, ji = (e) => {
  let i = 4093624447, t;
  for (t = 0; t <= 31; t++, i >>>= 1)
    if (i & 1 && e.dyn_ltree[t * 2] !== 0)
      return 0;
  if (e.dyn_ltree[18] !== 0 || e.dyn_ltree[20] !== 0 || e.dyn_ltree[26] !== 0)
    return 1;
  for (t = 32; t < Ae; t++)
    if (e.dyn_ltree[t * 2] !== 0)
      return 1;
  return 0;
};
let vt = !1;
const Wi = (e) => {
  vt || (Xi(), vt = !0), e.l_desc = new We(e.dyn_ltree, fi), e.d_desc = new We(e.dyn_dtree, oi), e.bl_desc = new We(e.bl_tree, _i), e.bi_buf = 0, e.bi_valid = 0, ci(e);
}, bi = (e, i, t, a) => {
  O(e, (Li << 1) + (a ? 1 : 0), 3), Pi(e, i, t);
}, Vi = (e) => {
  O(e, ti << 1, 3), M(e, ct, B), Bi(e);
}, Ji = (e, i, t, a) => {
  let n, l, o = 0;
  e.level > 0 ? (e.strm.data_type === 2 && (e.strm.data_type = ji(e)), ot(e, e.l_desc), ot(e, e.d_desc), o = Yi(e), n = e.opt_len + 3 + 7 >>> 3, l = e.static_len + 3 + 7 >>> 3, l <= n && (n = l)) : n = l = t + 5, t + 4 <= n && i !== -1 ? bi(e, i, t, a) : e.strategy === 4 || l === n ? (O(e, (ti << 1) + (a ? 1 : 0), 3), pt(e, B, ce)) : (O(e, (Ui << 1) + (a ? 1 : 0), 3), Gi(e, e.l_desc.max_code + 1, e.d_desc.max_code + 1, o + 1), pt(e, e.dyn_ltree, e.dyn_dtree)), ci(e), a && ui(e);
}, Qi = (e, i, t) => (e.pending_buf[e.d_buf + e.last_lit * 2] = i >>> 8 & 255, e.pending_buf[e.d_buf + e.last_lit * 2 + 1] = i & 255, e.pending_buf[e.l_buf + e.last_lit] = t & 255, e.last_lit++, i === 0 ? e.dyn_ltree[t * 2]++ : (e.matches++, i--, e.dyn_ltree[(pe[t] + Ae + 1) * 2]++, e.dyn_dtree[hi(i) * 2]++), e.last_lit === e.lit_bufsize - 1);
var qi = Wi, en = bi, tn = Ji, nn = Qi, an = Vi, ln = {
  _tr_init: qi,
  _tr_stored_block: en,
  _tr_flush_block: tn,
  _tr_tally: nn,
  _tr_align: an
};
const rn = (e, i, t, a) => {
  let n = e & 65535 | 0, l = e >>> 16 & 65535 | 0, o = 0;
  for (; t !== 0; ) {
    o = t > 2e3 ? 2e3 : t, t -= o;
    do
      n = n + i[a++] | 0, l = l + n | 0;
    while (--o);
    n %= 65521, l %= 65521;
  }
  return n | l << 16 | 0;
};
var ke = rn;
const fn = () => {
  let e, i = [];
  for (var t = 0; t < 256; t++) {
    e = t;
    for (var a = 0; a < 8; a++)
      e = e & 1 ? 3988292384 ^ e >>> 1 : e >>> 1;
    i[t] = e;
  }
  return i;
}, on = new Uint32Array(fn()), _n = (e, i, t, a) => {
  const n = on, l = a + t;
  e ^= -1;
  for (let o = a; o < l; o++)
    e = e >>> 8 ^ n[(e ^ i[o]) & 255];
  return e ^ -1;
};
var I = _n, ee = {
  2: "need dictionary",
  /* Z_NEED_DICT       2  */
  1: "stream end",
  /* Z_STREAM_END      1  */
  0: "",
  /* Z_OK              0  */
  "-1": "file error",
  /* Z_ERRNO         (-1) */
  "-2": "stream error",
  /* Z_STREAM_ERROR  (-2) */
  "-3": "data error",
  /* Z_DATA_ERROR    (-3) */
  "-4": "insufficient memory",
  /* Z_MEM_ERROR     (-4) */
  "-5": "buffer error",
  /* Z_BUF_ERROR     (-5) */
  "-6": "incompatible version"
  /* Z_VERSION_ERROR (-6) */
}, He = {
  /* Allowed flush values; see deflate() and inflate() below for details */
  Z_NO_FLUSH: 0,
  Z_PARTIAL_FLUSH: 1,
  Z_SYNC_FLUSH: 2,
  Z_FULL_FLUSH: 3,
  Z_FINISH: 4,
  Z_BLOCK: 5,
  Z_TREES: 6,
  /* Return codes for the compression/decompression functions. Negative values
  * are errors, positive values are used for special but normal events.
  */
  Z_OK: 0,
  Z_STREAM_END: 1,
  Z_NEED_DICT: 2,
  Z_STREAM_ERROR: -2,
  Z_DATA_ERROR: -3,
  Z_MEM_ERROR: -4,
  Z_BUF_ERROR: -5,
  Z_DEFAULT_COMPRESSION: -1,
  Z_FILTERED: 1,
  Z_HUFFMAN_ONLY: 2,
  Z_RLE: 3,
  Z_FIXED: 4,
  Z_DEFAULT_STRATEGY: 0,
  //Z_ASCII:                1, // = Z_TEXT (deprecated)
  Z_UNKNOWN: 2,
  /* The deflate compression method */
  Z_DEFLATED: 8
  //Z_NULL:                 null // Use -1 or null inline, depending on var type
};
const { _tr_init: hn, _tr_stored_block: dn, _tr_flush_block: sn, _tr_tally: j, _tr_align: cn } = ln, {
  Z_NO_FLUSH: ae,
  Z_PARTIAL_FLUSH: un,
  Z_FULL_FLUSH: bn,
  Z_FINISH: W,
  Z_BLOCK: Et,
  Z_OK: $,
  Z_STREAM_END: yt,
  Z_STREAM_ERROR: L,
  Z_DATA_ERROR: wn,
  Z_BUF_ERROR: Je,
  Z_DEFAULT_COMPRESSION: gn,
  Z_FILTERED: pn,
  Z_HUFFMAN_ONLY: Re,
  Z_RLE: xn,
  Z_FIXED: kn,
  Z_DEFAULT_STRATEGY: vn,
  Z_UNKNOWN: En,
  Z_DEFLATED: Be
} = He, yn = 9, An = 15, Sn = 8, zn = 29, Tn = 256, _t = Tn + 1 + zn, mn = 30, Rn = 19, Dn = 2 * _t + 1, Zn = 15, k = 3, Y = 258, C = Y + k + 1, In = 32, Ke = 42, ht = 69, Le = 73, Ue = 91, Ce = 103, q = 113, de = 666, D = 1, Se = 2, te = 3, _e = 4, Nn = 3, G = (e, i) => (e.msg = ee[i], i), At = (e) => (e << 1) - (e > 4 ? 9 : 0), P = (e) => {
  let i = e.length;
  for (; --i >= 0; )
    e[i] = 0;
};
let On = (e, i, t) => (i << e.hash_shift ^ t) & e.hash_mask, V = On;
const X = (e) => {
  const i = e.state;
  let t = i.pending;
  t > e.avail_out && (t = e.avail_out), t !== 0 && (e.output.set(i.pending_buf.subarray(i.pending_out, i.pending_out + t), e.next_out), e.next_out += t, i.pending_out += t, e.total_out += t, e.avail_out -= t, i.pending -= t, i.pending === 0 && (i.pending_out = 0));
}, N = (e, i) => {
  sn(e, e.block_start >= 0 ? e.block_start : -1, e.strstart - e.block_start, i), e.block_start = e.strstart, X(e.strm);
}, y = (e, i) => {
  e.pending_buf[e.pending++] = i;
}, he = (e, i) => {
  e.pending_buf[e.pending++] = i >>> 8 & 255, e.pending_buf[e.pending++] = i & 255;
}, Ln = (e, i, t, a) => {
  let n = e.avail_in;
  return n > a && (n = a), n === 0 ? 0 : (e.avail_in -= n, i.set(e.input.subarray(e.next_in, e.next_in + n), t), e.state.wrap === 1 ? e.adler = ke(e.adler, i, n, t) : e.state.wrap === 2 && (e.adler = I(e.adler, i, n, t)), e.next_in += n, e.total_in += n, n);
}, wi = (e, i) => {
  let t = e.max_chain_length, a = e.strstart, n, l, o = e.prev_length, f = e.nice_match;
  const c = e.strstart > e.w_size - C ? e.strstart - (e.w_size - C) : 0, r = e.window, _ = e.w_mask, E = e.prev, s = e.strstart + Y;
  let h = r[a + o - 1], u = r[a + o];
  e.prev_length >= e.good_match && (t >>= 2), f > e.lookahead && (f = e.lookahead);
  do
    if (n = i, !(r[n + o] !== u || r[n + o - 1] !== h || r[n] !== r[a] || r[++n] !== r[a + 1])) {
      a += 2, n++;
      do
        ;
      while (r[++a] === r[++n] && r[++a] === r[++n] && r[++a] === r[++n] && r[++a] === r[++n] && r[++a] === r[++n] && r[++a] === r[++n] && r[++a] === r[++n] && r[++a] === r[++n] && a < s);
      if (l = Y - (s - a), a = s - Y, l > o) {
        if (e.match_start = i, o = l, l >= f)
          break;
        h = r[a + o - 1], u = r[a + o];
      }
    }
  while ((i = E[i & _]) > c && --t !== 0);
  return o <= e.lookahead ? o : e.lookahead;
}, ie = (e) => {
  const i = e.w_size;
  let t, a, n, l, o;
  do {
    if (l = e.window_size - e.lookahead - e.strstart, e.strstart >= i + (i - C)) {
      e.window.set(e.window.subarray(i, i + i), 0), e.match_start -= i, e.strstart -= i, e.block_start -= i, a = e.hash_size, t = a;
      do
        n = e.head[--t], e.head[t] = n >= i ? n - i : 0;
      while (--a);
      a = i, t = a;
      do
        n = e.prev[--t], e.prev[t] = n >= i ? n - i : 0;
      while (--a);
      l += i;
    }
    if (e.strm.avail_in === 0)
      break;
    if (a = Ln(e.strm, e.window, e.strstart + e.lookahead, l), e.lookahead += a, e.lookahead + e.insert >= k)
      for (o = e.strstart - e.insert, e.ins_h = e.window[o], e.ins_h = V(e, e.ins_h, e.window[o + 1]); e.insert && (e.ins_h = V(e, e.ins_h, e.window[o + k - 1]), e.prev[o & e.w_mask] = e.head[e.ins_h], e.head[e.ins_h] = o, o++, e.insert--, !(e.lookahead + e.insert < k)); )
        ;
  } while (e.lookahead < C && e.strm.avail_in !== 0);
}, Un = (e, i) => {
  let t = 65535;
  for (t > e.pending_buf_size - 5 && (t = e.pending_buf_size - 5); ; ) {
    if (e.lookahead <= 1) {
      if (ie(e), e.lookahead === 0 && i === ae)
        return D;
      if (e.lookahead === 0)
        break;
    }
    e.strstart += e.lookahead, e.lookahead = 0;
    const a = e.block_start + t;
    if ((e.strstart === 0 || e.strstart >= a) && (e.lookahead = e.strstart - a, e.strstart = a, N(e, !1), e.strm.avail_out === 0) || e.strstart - e.block_start >= e.w_size - C && (N(e, !1), e.strm.avail_out === 0))
      return D;
  }
  return e.insert = 0, i === W ? (N(e, !0), e.strm.avail_out === 0 ? te : _e) : (e.strstart > e.block_start && (N(e, !1), e.strm.avail_out === 0), D);
}, Qe = (e, i) => {
  let t, a;
  for (; ; ) {
    if (e.lookahead < C) {
      if (ie(e), e.lookahead < C && i === ae)
        return D;
      if (e.lookahead === 0)
        break;
    }
    if (t = 0, e.lookahead >= k && (e.ins_h = V(e, e.ins_h, e.window[e.strstart + k - 1]), t = e.prev[e.strstart & e.w_mask] = e.head[e.ins_h], e.head[e.ins_h] = e.strstart), t !== 0 && e.strstart - t <= e.w_size - C && (e.match_length = wi(e, t)), e.match_length >= k)
      if (a = j(e, e.strstart - e.match_start, e.match_length - k), e.lookahead -= e.match_length, e.match_length <= e.max_lazy_match && e.lookahead >= k) {
        e.match_length--;
        do
          e.strstart++, e.ins_h = V(e, e.ins_h, e.window[e.strstart + k - 1]), t = e.prev[e.strstart & e.w_mask] = e.head[e.ins_h], e.head[e.ins_h] = e.strstart;
        while (--e.match_length !== 0);
        e.strstart++;
      } else
        e.strstart += e.match_length, e.match_length = 0, e.ins_h = e.window[e.strstart], e.ins_h = V(e, e.ins_h, e.window[e.strstart + 1]);
    else
      a = j(e, 0, e.window[e.strstart]), e.lookahead--, e.strstart++;
    if (a && (N(e, !1), e.strm.avail_out === 0))
      return D;
  }
  return e.insert = e.strstart < k - 1 ? e.strstart : k - 1, i === W ? (N(e, !0), e.strm.avail_out === 0 ? te : _e) : e.last_lit && (N(e, !1), e.strm.avail_out === 0) ? D : Se;
}, le = (e, i) => {
  let t, a, n;
  for (; ; ) {
    if (e.lookahead < C) {
      if (ie(e), e.lookahead < C && i === ae)
        return D;
      if (e.lookahead === 0)
        break;
    }
    if (t = 0, e.lookahead >= k && (e.ins_h = V(e, e.ins_h, e.window[e.strstart + k - 1]), t = e.prev[e.strstart & e.w_mask] = e.head[e.ins_h], e.head[e.ins_h] = e.strstart), e.prev_length = e.match_length, e.prev_match = e.match_start, e.match_length = k - 1, t !== 0 && e.prev_length < e.max_lazy_match && e.strstart - t <= e.w_size - C && (e.match_length = wi(e, t), e.match_length <= 5 && (e.strategy === pn || e.match_length === k && e.strstart - e.match_start > 4096) && (e.match_length = k - 1)), e.prev_length >= k && e.match_length <= e.prev_length) {
      n = e.strstart + e.lookahead - k, a = j(e, e.strstart - 1 - e.prev_match, e.prev_length - k), e.lookahead -= e.prev_length - 1, e.prev_length -= 2;
      do
        ++e.strstart <= n && (e.ins_h = V(e, e.ins_h, e.window[e.strstart + k - 1]), t = e.prev[e.strstart & e.w_mask] = e.head[e.ins_h], e.head[e.ins_h] = e.strstart);
      while (--e.prev_length !== 0);
      if (e.match_available = 0, e.match_length = k - 1, e.strstart++, a && (N(e, !1), e.strm.avail_out === 0))
        return D;
    } else if (e.match_available) {
      if (a = j(e, 0, e.window[e.strstart - 1]), a && N(e, !1), e.strstart++, e.lookahead--, e.strm.avail_out === 0)
        return D;
    } else
      e.match_available = 1, e.strstart++, e.lookahead--;
  }
  return e.match_available && (a = j(e, 0, e.window[e.strstart - 1]), e.match_available = 0), e.insert = e.strstart < k - 1 ? e.strstart : k - 1, i === W ? (N(e, !0), e.strm.avail_out === 0 ? te : _e) : e.last_lit && (N(e, !1), e.strm.avail_out === 0) ? D : Se;
}, Cn = (e, i) => {
  let t, a, n, l;
  const o = e.window;
  for (; ; ) {
    if (e.lookahead <= Y) {
      if (ie(e), e.lookahead <= Y && i === ae)
        return D;
      if (e.lookahead === 0)
        break;
    }
    if (e.match_length = 0, e.lookahead >= k && e.strstart > 0 && (n = e.strstart - 1, a = o[n], a === o[++n] && a === o[++n] && a === o[++n])) {
      l = e.strstart + Y;
      do
        ;
      while (a === o[++n] && a === o[++n] && a === o[++n] && a === o[++n] && a === o[++n] && a === o[++n] && a === o[++n] && a === o[++n] && n < l);
      e.match_length = Y - (l - n), e.match_length > e.lookahead && (e.match_length = e.lookahead);
    }
    if (e.match_length >= k ? (t = j(e, 1, e.match_length - k), e.lookahead -= e.match_length, e.strstart += e.match_length, e.match_length = 0) : (t = j(e, 0, e.window[e.strstart]), e.lookahead--, e.strstart++), t && (N(e, !1), e.strm.avail_out === 0))
      return D;
  }
  return e.insert = 0, i === W ? (N(e, !0), e.strm.avail_out === 0 ? te : _e) : e.last_lit && (N(e, !1), e.strm.avail_out === 0) ? D : Se;
}, Fn = (e, i) => {
  let t;
  for (; ; ) {
    if (e.lookahead === 0 && (ie(e), e.lookahead === 0)) {
      if (i === ae)
        return D;
      break;
    }
    if (e.match_length = 0, t = j(e, 0, e.window[e.strstart]), e.lookahead--, e.strstart++, t && (N(e, !1), e.strm.avail_out === 0))
      return D;
  }
  return e.insert = 0, i === W ? (N(e, !0), e.strm.avail_out === 0 ? te : _e) : e.last_lit && (N(e, !1), e.strm.avail_out === 0) ? D : Se;
};
function F(e, i, t, a, n) {
  this.good_length = e, this.max_lazy = i, this.nice_length = t, this.max_chain = a, this.func = n;
}
const se = [
  /*      good lazy nice chain */
  new F(0, 0, 0, 0, Un),
  /* 0 store only */
  new F(4, 4, 8, 4, Qe),
  /* 1 max speed, no lazy matches */
  new F(4, 5, 16, 8, Qe),
  /* 2 */
  new F(4, 6, 32, 32, Qe),
  /* 3 */
  new F(4, 4, 16, 16, le),
  /* 4 lazy matches */
  new F(8, 16, 32, 32, le),
  /* 5 */
  new F(8, 16, 128, 128, le),
  /* 6 */
  new F(8, 32, 128, 256, le),
  /* 7 */
  new F(32, 128, 258, 1024, le),
  /* 8 */
  new F(32, 258, 258, 4096, le)
  /* 9 max compression */
], Mn = (e) => {
  e.window_size = 2 * e.w_size, P(e.head), e.max_lazy_match = se[e.level].max_lazy, e.good_match = se[e.level].good_length, e.nice_match = se[e.level].nice_length, e.max_chain_length = se[e.level].max_chain, e.strstart = 0, e.block_start = 0, e.lookahead = 0, e.insert = 0, e.match_length = e.prev_length = k - 1, e.match_available = 0, e.ins_h = 0;
};
function $n() {
  this.strm = null, this.status = 0, this.pending_buf = null, this.pending_buf_size = 0, this.pending_out = 0, this.pending = 0, this.wrap = 0, this.gzhead = null, this.gzindex = 0, this.method = Be, this.last_flush = -1, this.w_size = 0, this.w_bits = 0, this.w_mask = 0, this.window = null, this.window_size = 0, this.prev = null, this.head = null, this.ins_h = 0, this.hash_size = 0, this.hash_bits = 0, this.hash_mask = 0, this.hash_shift = 0, this.block_start = 0, this.match_length = 0, this.prev_match = 0, this.match_available = 0, this.strstart = 0, this.match_start = 0, this.lookahead = 0, this.prev_length = 0, this.max_chain_length = 0, this.max_lazy_match = 0, this.level = 0, this.strategy = 0, this.good_match = 0, this.nice_match = 0, this.dyn_ltree = new Uint16Array(Dn * 2), this.dyn_dtree = new Uint16Array((2 * mn + 1) * 2), this.bl_tree = new Uint16Array((2 * Rn + 1) * 2), P(this.dyn_ltree), P(this.dyn_dtree), P(this.bl_tree), this.l_desc = null, this.d_desc = null, this.bl_desc = null, this.bl_count = new Uint16Array(Zn + 1), this.heap = new Uint16Array(2 * _t + 1), P(this.heap), this.heap_len = 0, this.heap_max = 0, this.depth = new Uint16Array(2 * _t + 1), P(this.depth), this.l_buf = 0, this.lit_bufsize = 0, this.last_lit = 0, this.d_buf = 0, this.opt_len = 0, this.static_len = 0, this.matches = 0, this.insert = 0, this.bi_buf = 0, this.bi_valid = 0;
}
const gi = (e) => {
  if (!e || !e.state)
    return G(e, L);
  e.total_in = e.total_out = 0, e.data_type = En;
  const i = e.state;
  return i.pending = 0, i.pending_out = 0, i.wrap < 0 && (i.wrap = -i.wrap), i.status = i.wrap ? Ke : q, e.adler = i.wrap === 2 ? 0 : 1, i.last_flush = ae, hn(i), $;
}, pi = (e) => {
  const i = gi(e);
  return i === $ && Mn(e.state), i;
}, Hn = (e, i) => !e || !e.state || e.state.wrap !== 2 ? L : (e.state.gzhead = i, $), xi = (e, i, t, a, n, l) => {
  if (!e)
    return L;
  let o = 1;
  if (i === gn && (i = 6), a < 0 ? (o = 0, a = -a) : a > 15 && (o = 2, a -= 16), n < 1 || n > yn || t !== Be || a < 8 || a > 15 || i < 0 || i > 9 || l < 0 || l > kn)
    return G(e, L);
  a === 8 && (a = 9);
  const f = new $n();
  return e.state = f, f.strm = e, f.wrap = o, f.gzhead = null, f.w_bits = a, f.w_size = 1 << f.w_bits, f.w_mask = f.w_size - 1, f.hash_bits = n + 7, f.hash_size = 1 << f.hash_bits, f.hash_mask = f.hash_size - 1, f.hash_shift = ~~((f.hash_bits + k - 1) / k), f.window = new Uint8Array(f.w_size * 2), f.head = new Uint16Array(f.hash_size), f.prev = new Uint16Array(f.w_size), f.lit_bufsize = 1 << n + 6, f.pending_buf_size = f.lit_bufsize * 4, f.pending_buf = new Uint8Array(f.pending_buf_size), f.d_buf = 1 * f.lit_bufsize, f.l_buf = 3 * f.lit_bufsize, f.level = i, f.strategy = l, f.method = t, pi(e);
}, Bn = (e, i) => xi(e, i, Be, An, Sn, vn), Kn = (e, i) => {
  let t, a;
  if (!e || !e.state || i > Et || i < 0)
    return e ? G(e, L) : L;
  const n = e.state;
  if (!e.output || !e.input && e.avail_in !== 0 || n.status === de && i !== W)
    return G(e, e.avail_out === 0 ? Je : L);
  n.strm = e;
  const l = n.last_flush;
  if (n.last_flush = i, n.status === Ke)
    if (n.wrap === 2)
      e.adler = 0, y(n, 31), y(n, 139), y(n, 8), n.gzhead ? (y(
        n,
        (n.gzhead.text ? 1 : 0) + (n.gzhead.hcrc ? 2 : 0) + (n.gzhead.extra ? 4 : 0) + (n.gzhead.name ? 8 : 0) + (n.gzhead.comment ? 16 : 0)
      ), y(n, n.gzhead.time & 255), y(n, n.gzhead.time >> 8 & 255), y(n, n.gzhead.time >> 16 & 255), y(n, n.gzhead.time >> 24 & 255), y(n, n.level === 9 ? 2 : n.strategy >= Re || n.level < 2 ? 4 : 0), y(n, n.gzhead.os & 255), n.gzhead.extra && n.gzhead.extra.length && (y(n, n.gzhead.extra.length & 255), y(n, n.gzhead.extra.length >> 8 & 255)), n.gzhead.hcrc && (e.adler = I(e.adler, n.pending_buf, n.pending, 0)), n.gzindex = 0, n.status = ht) : (y(n, 0), y(n, 0), y(n, 0), y(n, 0), y(n, 0), y(n, n.level === 9 ? 2 : n.strategy >= Re || n.level < 2 ? 4 : 0), y(n, Nn), n.status = q);
    else {
      let o = Be + (n.w_bits - 8 << 4) << 8, f = -1;
      n.strategy >= Re || n.level < 2 ? f = 0 : n.level < 6 ? f = 1 : n.level === 6 ? f = 2 : f = 3, o |= f << 6, n.strstart !== 0 && (o |= In), o += 31 - o % 31, n.status = q, he(n, o), n.strstart !== 0 && (he(n, e.adler >>> 16), he(n, e.adler & 65535)), e.adler = 1;
    }
  if (n.status === ht)
    if (n.gzhead.extra) {
      for (t = n.pending; n.gzindex < (n.gzhead.extra.length & 65535) && !(n.pending === n.pending_buf_size && (n.gzhead.hcrc && n.pending > t && (e.adler = I(e.adler, n.pending_buf, n.pending - t, t)), X(e), t = n.pending, n.pending === n.pending_buf_size)); )
        y(n, n.gzhead.extra[n.gzindex] & 255), n.gzindex++;
      n.gzhead.hcrc && n.pending > t && (e.adler = I(e.adler, n.pending_buf, n.pending - t, t)), n.gzindex === n.gzhead.extra.length && (n.gzindex = 0, n.status = Le);
    } else
      n.status = Le;
  if (n.status === Le)
    if (n.gzhead.name) {
      t = n.pending;
      do {
        if (n.pending === n.pending_buf_size && (n.gzhead.hcrc && n.pending > t && (e.adler = I(e.adler, n.pending_buf, n.pending - t, t)), X(e), t = n.pending, n.pending === n.pending_buf_size)) {
          a = 1;
          break;
        }
        n.gzindex < n.gzhead.name.length ? a = n.gzhead.name.charCodeAt(n.gzindex++) & 255 : a = 0, y(n, a);
      } while (a !== 0);
      n.gzhead.hcrc && n.pending > t && (e.adler = I(e.adler, n.pending_buf, n.pending - t, t)), a === 0 && (n.gzindex = 0, n.status = Ue);
    } else
      n.status = Ue;
  if (n.status === Ue)
    if (n.gzhead.comment) {
      t = n.pending;
      do {
        if (n.pending === n.pending_buf_size && (n.gzhead.hcrc && n.pending > t && (e.adler = I(e.adler, n.pending_buf, n.pending - t, t)), X(e), t = n.pending, n.pending === n.pending_buf_size)) {
          a = 1;
          break;
        }
        n.gzindex < n.gzhead.comment.length ? a = n.gzhead.comment.charCodeAt(n.gzindex++) & 255 : a = 0, y(n, a);
      } while (a !== 0);
      n.gzhead.hcrc && n.pending > t && (e.adler = I(e.adler, n.pending_buf, n.pending - t, t)), a === 0 && (n.status = Ce);
    } else
      n.status = Ce;
  if (n.status === Ce && (n.gzhead.hcrc ? (n.pending + 2 > n.pending_buf_size && X(e), n.pending + 2 <= n.pending_buf_size && (y(n, e.adler & 255), y(n, e.adler >> 8 & 255), e.adler = 0, n.status = q)) : n.status = q), n.pending !== 0) {
    if (X(e), e.avail_out === 0)
      return n.last_flush = -1, $;
  } else if (e.avail_in === 0 && At(i) <= At(l) && i !== W)
    return G(e, Je);
  if (n.status === de && e.avail_in !== 0)
    return G(e, Je);
  if (e.avail_in !== 0 || n.lookahead !== 0 || i !== ae && n.status !== de) {
    let o = n.strategy === Re ? Fn(n, i) : n.strategy === xn ? Cn(n, i) : se[n.level].func(n, i);
    if ((o === te || o === _e) && (n.status = de), o === D || o === te)
      return e.avail_out === 0 && (n.last_flush = -1), $;
    if (o === Se && (i === un ? cn(n) : i !== Et && (dn(n, 0, 0, !1), i === bn && (P(n.head), n.lookahead === 0 && (n.strstart = 0, n.block_start = 0, n.insert = 0))), X(e), e.avail_out === 0))
      return n.last_flush = -1, $;
  }
  return i !== W ? $ : n.wrap <= 0 ? yt : (n.wrap === 2 ? (y(n, e.adler & 255), y(n, e.adler >> 8 & 255), y(n, e.adler >> 16 & 255), y(n, e.adler >> 24 & 255), y(n, e.total_in & 255), y(n, e.total_in >> 8 & 255), y(n, e.total_in >> 16 & 255), y(n, e.total_in >> 24 & 255)) : (he(n, e.adler >>> 16), he(n, e.adler & 65535)), X(e), n.wrap > 0 && (n.wrap = -n.wrap), n.pending !== 0 ? $ : yt);
}, Xn = (e) => {
  if (!e || !e.state)
    return L;
  const i = e.state.status;
  return i !== Ke && i !== ht && i !== Le && i !== Ue && i !== Ce && i !== q && i !== de ? G(e, L) : (e.state = null, i === q ? G(e, wn) : $);
}, Pn = (e, i) => {
  let t = i.length;
  if (!e || !e.state)
    return L;
  const a = e.state, n = a.wrap;
  if (n === 2 || n === 1 && a.status !== Ke || a.lookahead)
    return L;
  if (n === 1 && (e.adler = ke(e.adler, i, t, 0)), a.wrap = 0, t >= a.w_size) {
    n === 0 && (P(a.head), a.strstart = 0, a.block_start = 0, a.insert = 0);
    let c = new Uint8Array(a.w_size);
    c.set(i.subarray(t - a.w_size, t), 0), i = c, t = a.w_size;
  }
  const l = e.avail_in, o = e.next_in, f = e.input;
  for (e.avail_in = t, e.next_in = 0, e.input = i, ie(a); a.lookahead >= k; ) {
    let c = a.strstart, r = a.lookahead - (k - 1);
    do
      a.ins_h = V(a, a.ins_h, a.window[c + k - 1]), a.prev[c & a.w_mask] = a.head[a.ins_h], a.head[a.ins_h] = c, c++;
    while (--r);
    a.strstart = c, a.lookahead = k - 1, ie(a);
  }
  return a.strstart += a.lookahead, a.block_start = a.strstart, a.insert = a.lookahead, a.lookahead = 0, a.match_length = a.prev_length = k - 1, a.match_available = 0, e.next_in = o, e.input = f, e.avail_in = l, a.wrap = n, $;
};
var Yn = Bn, Gn = xi, jn = pi, Wn = gi, Vn = Hn, Jn = Kn, Qn = Xn, qn = Pn, ea = "pako deflate (from Nodeca project)", ue = {
  deflateInit: Yn,
  deflateInit2: Gn,
  deflateReset: jn,
  deflateResetKeep: Wn,
  deflateSetHeader: Vn,
  deflate: Jn,
  deflateEnd: Qn,
  deflateSetDictionary: qn,
  deflateInfo: ea
};
const ta = (e, i) => Object.prototype.hasOwnProperty.call(e, i);
var ia = function(e) {
  const i = Array.prototype.slice.call(arguments, 1);
  for (; i.length; ) {
    const t = i.shift();
    if (t) {
      if (typeof t != "object")
        throw new TypeError(t + "must be non-object");
      for (const a in t)
        ta(t, a) && (e[a] = t[a]);
    }
  }
  return e;
}, na = (e) => {
  let i = 0;
  for (let a = 0, n = e.length; a < n; a++)
    i += e[a].length;
  const t = new Uint8Array(i);
  for (let a = 0, n = 0, l = e.length; a < l; a++) {
    let o = e[a];
    t.set(o, n), n += o.length;
  }
  return t;
}, Xe = {
  assign: ia,
  flattenChunks: na
};
let ki = !0;
try {
  String.fromCharCode.apply(null, new Uint8Array(1));
} catch {
  ki = !1;
}
const ve = new Uint8Array(256);
for (let e = 0; e < 256; e++)
  ve[e] = e >= 252 ? 6 : e >= 248 ? 5 : e >= 240 ? 4 : e >= 224 ? 3 : e >= 192 ? 2 : 1;
ve[254] = ve[254] = 1;
var aa = (e) => {
  let i, t, a, n, l, o = e.length, f = 0;
  for (n = 0; n < o; n++)
    t = e.charCodeAt(n), (t & 64512) === 55296 && n + 1 < o && (a = e.charCodeAt(n + 1), (a & 64512) === 56320 && (t = 65536 + (t - 55296 << 10) + (a - 56320), n++)), f += t < 128 ? 1 : t < 2048 ? 2 : t < 65536 ? 3 : 4;
  for (i = new Uint8Array(f), l = 0, n = 0; l < f; n++)
    t = e.charCodeAt(n), (t & 64512) === 55296 && n + 1 < o && (a = e.charCodeAt(n + 1), (a & 64512) === 56320 && (t = 65536 + (t - 55296 << 10) + (a - 56320), n++)), t < 128 ? i[l++] = t : t < 2048 ? (i[l++] = 192 | t >>> 6, i[l++] = 128 | t & 63) : t < 65536 ? (i[l++] = 224 | t >>> 12, i[l++] = 128 | t >>> 6 & 63, i[l++] = 128 | t & 63) : (i[l++] = 240 | t >>> 18, i[l++] = 128 | t >>> 12 & 63, i[l++] = 128 | t >>> 6 & 63, i[l++] = 128 | t & 63);
  return i;
};
const la = (e, i) => {
  if (i < 65534 && e.subarray && ki)
    return String.fromCharCode.apply(null, e.length === i ? e : e.subarray(0, i));
  let t = "";
  for (let a = 0; a < i; a++)
    t += String.fromCharCode(e[a]);
  return t;
};
var ra = (e, i) => {
  let t, a;
  const n = i || e.length, l = new Array(n * 2);
  for (a = 0, t = 0; t < n; ) {
    let o = e[t++];
    if (o < 128) {
      l[a++] = o;
      continue;
    }
    let f = ve[o];
    if (f > 4) {
      l[a++] = 65533, t += f - 1;
      continue;
    }
    for (o &= f === 2 ? 31 : f === 3 ? 15 : 7; f > 1 && t < n; )
      o = o << 6 | e[t++] & 63, f--;
    if (f > 1) {
      l[a++] = 65533;
      continue;
    }
    o < 65536 ? l[a++] = o : (o -= 65536, l[a++] = 55296 | o >> 10 & 1023, l[a++] = 56320 | o & 1023);
  }
  return la(l, a);
}, fa = (e, i) => {
  i = i || e.length, i > e.length && (i = e.length);
  let t = i - 1;
  for (; t >= 0 && (e[t] & 192) === 128; )
    t--;
  return t < 0 || t === 0 ? i : t + ve[e[t]] > i ? t : i;
}, Ee = {
  string2buf: aa,
  buf2string: ra,
  utf8border: fa
};
function oa() {
  this.input = null, this.next_in = 0, this.avail_in = 0, this.total_in = 0, this.output = null, this.next_out = 0, this.avail_out = 0, this.total_out = 0, this.msg = "", this.state = null, this.data_type = 2, this.adler = 0;
}
var vi = oa;
const Ei = Object.prototype.toString, {
  Z_NO_FLUSH: _a,
  Z_SYNC_FLUSH: ha,
  Z_FULL_FLUSH: da,
  Z_FINISH: sa,
  Z_OK: Me,
  Z_STREAM_END: ca,
  Z_DEFAULT_COMPRESSION: ua,
  Z_DEFAULT_STRATEGY: ba,
  Z_DEFLATED: wa
} = He;
function Pe(e) {
  this.options = Xe.assign({
    level: ua,
    method: wa,
    chunkSize: 16384,
    windowBits: 15,
    memLevel: 8,
    strategy: ba
  }, e || {});
  let i = this.options;
  i.raw && i.windowBits > 0 ? i.windowBits = -i.windowBits : i.gzip && i.windowBits > 0 && i.windowBits < 16 && (i.windowBits += 16), this.err = 0, this.msg = "", this.ended = !1, this.chunks = [], this.strm = new vi(), this.strm.avail_out = 0;
  let t = ue.deflateInit2(
    this.strm,
    i.level,
    i.method,
    i.windowBits,
    i.memLevel,
    i.strategy
  );
  if (t !== Me)
    throw new Error(ee[t]);
  if (i.header && ue.deflateSetHeader(this.strm, i.header), i.dictionary) {
    let a;
    if (typeof i.dictionary == "string" ? a = Ee.string2buf(i.dictionary) : Ei.call(i.dictionary) === "[object ArrayBuffer]" ? a = new Uint8Array(i.dictionary) : a = i.dictionary, t = ue.deflateSetDictionary(this.strm, a), t !== Me)
      throw new Error(ee[t]);
    this._dict_set = !0;
  }
}
Pe.prototype.push = function(e, i) {
  const t = this.strm, a = this.options.chunkSize;
  let n, l;
  if (this.ended)
    return !1;
  for (i === ~~i ? l = i : l = i === !0 ? sa : _a, typeof e == "string" ? t.input = Ee.string2buf(e) : Ei.call(e) === "[object ArrayBuffer]" ? t.input = new Uint8Array(e) : t.input = e, t.next_in = 0, t.avail_in = t.input.length; ; ) {
    if (t.avail_out === 0 && (t.output = new Uint8Array(a), t.next_out = 0, t.avail_out = a), (l === ha || l === da) && t.avail_out <= 6) {
      this.onData(t.output.subarray(0, t.next_out)), t.avail_out = 0;
      continue;
    }
    if (n = ue.deflate(t, l), n === ca)
      return t.next_out > 0 && this.onData(t.output.subarray(0, t.next_out)), n = ue.deflateEnd(this.strm), this.onEnd(n), this.ended = !0, n === Me;
    if (t.avail_out === 0) {
      this.onData(t.output);
      continue;
    }
    if (l > 0 && t.next_out > 0) {
      this.onData(t.output.subarray(0, t.next_out)), t.avail_out = 0;
      continue;
    }
    if (t.avail_in === 0) break;
  }
  return !0;
};
Pe.prototype.onData = function(e) {
  this.chunks.push(e);
};
Pe.prototype.onEnd = function(e) {
  e === Me && (this.result = Xe.flattenChunks(this.chunks)), this.chunks = [], this.err = e, this.msg = this.strm.msg;
};
function ga(e, i) {
  const t = new Pe(i);
  if (t.push(e, !0), t.err)
    throw t.msg || ee[t.err];
  return t.result;
}
var pa = ga, xa = {
  deflate: pa
};
const De = 30, ka = 12;
var va = function(i, t) {
  let a, n, l, o, f, c, r, _, E, s, h, u, R, v, w, S, x, d, A, Z, b, T, z, g;
  const p = i.state;
  a = i.next_in, z = i.input, n = a + (i.avail_in - 5), l = i.next_out, g = i.output, o = l - (t - i.avail_out), f = l + (i.avail_out - 257), c = p.dmax, r = p.wsize, _ = p.whave, E = p.wnext, s = p.window, h = p.hold, u = p.bits, R = p.lencode, v = p.distcode, w = (1 << p.lenbits) - 1, S = (1 << p.distbits) - 1;
  e:
    do {
      u < 15 && (h += z[a++] << u, u += 8, h += z[a++] << u, u += 8), x = R[h & w];
      t:
        for (; ; ) {
          if (d = x >>> 24, h >>>= d, u -= d, d = x >>> 16 & 255, d === 0)
            g[l++] = x & 65535;
          else if (d & 16) {
            A = x & 65535, d &= 15, d && (u < d && (h += z[a++] << u, u += 8), A += h & (1 << d) - 1, h >>>= d, u -= d), u < 15 && (h += z[a++] << u, u += 8, h += z[a++] << u, u += 8), x = v[h & S];
            i:
              for (; ; ) {
                if (d = x >>> 24, h >>>= d, u -= d, d = x >>> 16 & 255, d & 16) {
                  if (Z = x & 65535, d &= 15, u < d && (h += z[a++] << u, u += 8, u < d && (h += z[a++] << u, u += 8)), Z += h & (1 << d) - 1, Z > c) {
                    i.msg = "invalid distance too far back", p.mode = De;
                    break e;
                  }
                  if (h >>>= d, u -= d, d = l - o, Z > d) {
                    if (d = Z - d, d > _ && p.sane) {
                      i.msg = "invalid distance too far back", p.mode = De;
                      break e;
                    }
                    if (b = 0, T = s, E === 0) {
                      if (b += r - d, d < A) {
                        A -= d;
                        do
                          g[l++] = s[b++];
                        while (--d);
                        b = l - Z, T = g;
                      }
                    } else if (E < d) {
                      if (b += r + E - d, d -= E, d < A) {
                        A -= d;
                        do
                          g[l++] = s[b++];
                        while (--d);
                        if (b = 0, E < A) {
                          d = E, A -= d;
                          do
                            g[l++] = s[b++];
                          while (--d);
                          b = l - Z, T = g;
                        }
                      }
                    } else if (b += E - d, d < A) {
                      A -= d;
                      do
                        g[l++] = s[b++];
                      while (--d);
                      b = l - Z, T = g;
                    }
                    for (; A > 2; )
                      g[l++] = T[b++], g[l++] = T[b++], g[l++] = T[b++], A -= 3;
                    A && (g[l++] = T[b++], A > 1 && (g[l++] = T[b++]));
                  } else {
                    b = l - Z;
                    do
                      g[l++] = g[b++], g[l++] = g[b++], g[l++] = g[b++], A -= 3;
                    while (A > 2);
                    A && (g[l++] = g[b++], A > 1 && (g[l++] = g[b++]));
                  }
                } else if ((d & 64) === 0) {
                  x = v[(x & 65535) + (h & (1 << d) - 1)];
                  continue i;
                } else {
                  i.msg = "invalid distance code", p.mode = De;
                  break e;
                }
                break;
              }
          } else if ((d & 64) === 0) {
            x = R[(x & 65535) + (h & (1 << d) - 1)];
            continue t;
          } else if (d & 32) {
            p.mode = ka;
            break e;
          } else {
            i.msg = "invalid literal/length code", p.mode = De;
            break e;
          }
          break;
        }
    } while (a < n && l < f);
  A = u >> 3, a -= A, u -= A << 3, h &= (1 << u) - 1, i.next_in = a, i.next_out = l, i.avail_in = a < n ? 5 + (n - a) : 5 - (a - n), i.avail_out = l < f ? 257 + (f - l) : 257 - (l - f), p.hold = h, p.bits = u;
};
const re = 15, St = 852, zt = 592, Tt = 0, qe = 1, mt = 2, Ea = new Uint16Array([
  /* Length codes 257..285 base */
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  13,
  15,
  17,
  19,
  23,
  27,
  31,
  35,
  43,
  51,
  59,
  67,
  83,
  99,
  115,
  131,
  163,
  195,
  227,
  258,
  0,
  0
]), ya = new Uint8Array([
  /* Length codes 257..285 extra */
  16,
  16,
  16,
  16,
  16,
  16,
  16,
  16,
  17,
  17,
  17,
  17,
  18,
  18,
  18,
  18,
  19,
  19,
  19,
  19,
  20,
  20,
  20,
  20,
  21,
  21,
  21,
  21,
  16,
  72,
  78
]), Aa = new Uint16Array([
  /* Distance codes 0..29 base */
  1,
  2,
  3,
  4,
  5,
  7,
  9,
  13,
  17,
  25,
  33,
  49,
  65,
  97,
  129,
  193,
  257,
  385,
  513,
  769,
  1025,
  1537,
  2049,
  3073,
  4097,
  6145,
  8193,
  12289,
  16385,
  24577,
  0,
  0
]), Sa = new Uint8Array([
  /* Distance codes 0..29 extra */
  16,
  16,
  16,
  16,
  17,
  17,
  18,
  18,
  19,
  19,
  20,
  20,
  21,
  21,
  22,
  22,
  23,
  23,
  24,
  24,
  25,
  25,
  26,
  26,
  27,
  27,
  28,
  28,
  29,
  29,
  64,
  64
]), za = (e, i, t, a, n, l, o, f) => {
  const c = f.bits;
  let r = 0, _ = 0, E = 0, s = 0, h = 0, u = 0, R = 0, v = 0, w = 0, S = 0, x, d, A, Z, b, T = null, z = 0, g;
  const p = new Uint16Array(re + 1), J = new Uint16Array(re + 1);
  let ze = null, bt = 0, wt, Te, me;
  for (r = 0; r <= re; r++)
    p[r] = 0;
  for (_ = 0; _ < a; _++)
    p[i[t + _]]++;
  for (h = c, s = re; s >= 1 && p[s] === 0; s--)
    ;
  if (h > s && (h = s), s === 0)
    return n[l++] = 1 << 24 | 64 << 16 | 0, n[l++] = 1 << 24 | 64 << 16 | 0, f.bits = 1, 0;
  for (E = 1; E < s && p[E] === 0; E++)
    ;
  for (h < E && (h = E), v = 1, r = 1; r <= re; r++)
    if (v <<= 1, v -= p[r], v < 0)
      return -1;
  if (v > 0 && (e === Tt || s !== 1))
    return -1;
  for (J[1] = 0, r = 1; r < re; r++)
    J[r + 1] = J[r] + p[r];
  for (_ = 0; _ < a; _++)
    i[t + _] !== 0 && (o[J[i[t + _]]++] = _);
  if (e === Tt ? (T = ze = o, g = 19) : e === qe ? (T = Ea, z -= 257, ze = ya, bt -= 257, g = 256) : (T = Aa, ze = Sa, g = -1), S = 0, _ = 0, r = E, b = l, u = h, R = 0, A = -1, w = 1 << h, Z = w - 1, e === qe && w > St || e === mt && w > zt)
    return 1;
  for (; ; ) {
    wt = r - R, o[_] < g ? (Te = 0, me = o[_]) : o[_] > g ? (Te = ze[bt + o[_]], me = T[z + o[_]]) : (Te = 96, me = 0), x = 1 << r - R, d = 1 << u, E = d;
    do
      d -= x, n[b + (S >> R) + d] = wt << 24 | Te << 16 | me | 0;
    while (d !== 0);
    for (x = 1 << r - 1; S & x; )
      x >>= 1;
    if (x !== 0 ? (S &= x - 1, S += x) : S = 0, _++, --p[r] === 0) {
      if (r === s)
        break;
      r = i[t + o[_]];
    }
    if (r > h && (S & Z) !== A) {
      for (R === 0 && (R = h), b += E, u = r - R, v = 1 << u; u + R < s && (v -= p[u + R], !(v <= 0)); )
        u++, v <<= 1;
      if (w += 1 << u, e === qe && w > St || e === mt && w > zt)
        return 1;
      A = S & Z, n[A] = h << 24 | u << 16 | b - l | 0;
    }
  }
  return S !== 0 && (n[b + S] = r - R << 24 | 64 << 16 | 0), f.bits = h, 0;
};
var be = za;
const Ta = 0, yi = 1, Ai = 2, {
  Z_FINISH: Rt,
  Z_BLOCK: ma,
  Z_TREES: Ze,
  Z_OK: ne,
  Z_STREAM_END: Ra,
  Z_NEED_DICT: Da,
  Z_STREAM_ERROR: U,
  Z_DATA_ERROR: Si,
  Z_MEM_ERROR: zi,
  Z_BUF_ERROR: Za,
  Z_DEFLATED: Dt
} = He, Ti = 1, Zt = 2, It = 3, Nt = 4, Ot = 5, Lt = 6, Ut = 7, Ct = 8, Ft = 9, Mt = 10, $e = 11, H = 12, et = 13, $t = 14, tt = 15, Ht = 16, Bt = 17, Kt = 18, Xt = 19, Ie = 20, Ne = 21, Pt = 22, Yt = 23, Gt = 24, jt = 25, Wt = 26, it = 27, Vt = 28, Jt = 29, m = 30, mi = 31, Ia = 32, Na = 852, Oa = 592, La = 15, Ua = La, Qt = (e) => (e >>> 24 & 255) + (e >>> 8 & 65280) + ((e & 65280) << 8) + ((e & 255) << 24);
function Ca() {
  this.mode = 0, this.last = !1, this.wrap = 0, this.havedict = !1, this.flags = 0, this.dmax = 0, this.check = 0, this.total = 0, this.head = null, this.wbits = 0, this.wsize = 0, this.whave = 0, this.wnext = 0, this.window = null, this.hold = 0, this.bits = 0, this.length = 0, this.offset = 0, this.extra = 0, this.lencode = null, this.distcode = null, this.lenbits = 0, this.distbits = 0, this.ncode = 0, this.nlen = 0, this.ndist = 0, this.have = 0, this.next = null, this.lens = new Uint16Array(320), this.work = new Uint16Array(288), this.lendyn = null, this.distdyn = null, this.sane = 0, this.back = 0, this.was = 0;
}
const Ri = (e) => {
  if (!e || !e.state)
    return U;
  const i = e.state;
  return e.total_in = e.total_out = i.total = 0, e.msg = "", i.wrap && (e.adler = i.wrap & 1), i.mode = Ti, i.last = 0, i.havedict = 0, i.dmax = 32768, i.head = null, i.hold = 0, i.bits = 0, i.lencode = i.lendyn = new Int32Array(Na), i.distcode = i.distdyn = new Int32Array(Oa), i.sane = 1, i.back = -1, ne;
}, Di = (e) => {
  if (!e || !e.state)
    return U;
  const i = e.state;
  return i.wsize = 0, i.whave = 0, i.wnext = 0, Ri(e);
}, Zi = (e, i) => {
  let t;
  if (!e || !e.state)
    return U;
  const a = e.state;
  return i < 0 ? (t = 0, i = -i) : (t = (i >> 4) + 1, i < 48 && (i &= 15)), i && (i < 8 || i > 15) ? U : (a.window !== null && a.wbits !== i && (a.window = null), a.wrap = t, a.wbits = i, Di(e));
}, Ii = (e, i) => {
  if (!e)
    return U;
  const t = new Ca();
  e.state = t, t.window = null;
  const a = Zi(e, i);
  return a !== ne && (e.state = null), a;
}, Fa = (e) => Ii(e, Ua);
let qt = !0, nt, at;
const Ma = (e) => {
  if (qt) {
    nt = new Int32Array(512), at = new Int32Array(32);
    let i = 0;
    for (; i < 144; )
      e.lens[i++] = 8;
    for (; i < 256; )
      e.lens[i++] = 9;
    for (; i < 280; )
      e.lens[i++] = 7;
    for (; i < 288; )
      e.lens[i++] = 8;
    for (be(yi, e.lens, 0, 288, nt, 0, e.work, { bits: 9 }), i = 0; i < 32; )
      e.lens[i++] = 5;
    be(Ai, e.lens, 0, 32, at, 0, e.work, { bits: 5 }), qt = !1;
  }
  e.lencode = nt, e.lenbits = 9, e.distcode = at, e.distbits = 5;
}, Ni = (e, i, t, a) => {
  let n;
  const l = e.state;
  return l.window === null && (l.wsize = 1 << l.wbits, l.wnext = 0, l.whave = 0, l.window = new Uint8Array(l.wsize)), a >= l.wsize ? (l.window.set(i.subarray(t - l.wsize, t), 0), l.wnext = 0, l.whave = l.wsize) : (n = l.wsize - l.wnext, n > a && (n = a), l.window.set(i.subarray(t - a, t - a + n), l.wnext), a -= n, a ? (l.window.set(i.subarray(t - a, t), 0), l.wnext = a, l.whave = l.wsize) : (l.wnext += n, l.wnext === l.wsize && (l.wnext = 0), l.whave < l.wsize && (l.whave += n))), 0;
}, $a = (e, i) => {
  let t, a, n, l, o, f, c, r, _, E, s, h, u, R, v = 0, w, S, x, d, A, Z, b, T;
  const z = new Uint8Array(4);
  let g, p;
  const J = (
    /* permutation of code lengths */
    new Uint8Array([16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15])
  );
  if (!e || !e.state || !e.output || !e.input && e.avail_in !== 0)
    return U;
  t = e.state, t.mode === H && (t.mode = et), o = e.next_out, n = e.output, c = e.avail_out, l = e.next_in, a = e.input, f = e.avail_in, r = t.hold, _ = t.bits, E = f, s = c, T = ne;
  e:
    for (; ; )
      switch (t.mode) {
        case Ti:
          if (t.wrap === 0) {
            t.mode = et;
            break;
          }
          for (; _ < 16; ) {
            if (f === 0)
              break e;
            f--, r += a[l++] << _, _ += 8;
          }
          if (t.wrap & 2 && r === 35615) {
            t.check = 0, z[0] = r & 255, z[1] = r >>> 8 & 255, t.check = I(t.check, z, 2, 0), r = 0, _ = 0, t.mode = Zt;
            break;
          }
          if (t.flags = 0, t.head && (t.head.done = !1), !(t.wrap & 1) || /* check if zlib header allowed */
          (((r & 255) << 8) + (r >> 8)) % 31) {
            e.msg = "incorrect header check", t.mode = m;
            break;
          }
          if ((r & 15) !== Dt) {
            e.msg = "unknown compression method", t.mode = m;
            break;
          }
          if (r >>>= 4, _ -= 4, b = (r & 15) + 8, t.wbits === 0)
            t.wbits = b;
          else if (b > t.wbits) {
            e.msg = "invalid window size", t.mode = m;
            break;
          }
          t.dmax = 1 << t.wbits, e.adler = t.check = 1, t.mode = r & 512 ? Mt : H, r = 0, _ = 0;
          break;
        case Zt:
          for (; _ < 16; ) {
            if (f === 0)
              break e;
            f--, r += a[l++] << _, _ += 8;
          }
          if (t.flags = r, (t.flags & 255) !== Dt) {
            e.msg = "unknown compression method", t.mode = m;
            break;
          }
          if (t.flags & 57344) {
            e.msg = "unknown header flags set", t.mode = m;
            break;
          }
          t.head && (t.head.text = r >> 8 & 1), t.flags & 512 && (z[0] = r & 255, z[1] = r >>> 8 & 255, t.check = I(t.check, z, 2, 0)), r = 0, _ = 0, t.mode = It;
        /* falls through */
        case It:
          for (; _ < 32; ) {
            if (f === 0)
              break e;
            f--, r += a[l++] << _, _ += 8;
          }
          t.head && (t.head.time = r), t.flags & 512 && (z[0] = r & 255, z[1] = r >>> 8 & 255, z[2] = r >>> 16 & 255, z[3] = r >>> 24 & 255, t.check = I(t.check, z, 4, 0)), r = 0, _ = 0, t.mode = Nt;
        /* falls through */
        case Nt:
          for (; _ < 16; ) {
            if (f === 0)
              break e;
            f--, r += a[l++] << _, _ += 8;
          }
          t.head && (t.head.xflags = r & 255, t.head.os = r >> 8), t.flags & 512 && (z[0] = r & 255, z[1] = r >>> 8 & 255, t.check = I(t.check, z, 2, 0)), r = 0, _ = 0, t.mode = Ot;
        /* falls through */
        case Ot:
          if (t.flags & 1024) {
            for (; _ < 16; ) {
              if (f === 0)
                break e;
              f--, r += a[l++] << _, _ += 8;
            }
            t.length = r, t.head && (t.head.extra_len = r), t.flags & 512 && (z[0] = r & 255, z[1] = r >>> 8 & 255, t.check = I(t.check, z, 2, 0)), r = 0, _ = 0;
          } else t.head && (t.head.extra = null);
          t.mode = Lt;
        /* falls through */
        case Lt:
          if (t.flags & 1024 && (h = t.length, h > f && (h = f), h && (t.head && (b = t.head.extra_len - t.length, t.head.extra || (t.head.extra = new Uint8Array(t.head.extra_len)), t.head.extra.set(
            a.subarray(
              l,
              // extra field is limited to 65536 bytes
              // - no need for additional size check
              l + h
            ),
            /*len + copy > state.head.extra_max - len ? state.head.extra_max : copy,*/
            b
          )), t.flags & 512 && (t.check = I(t.check, a, h, l)), f -= h, l += h, t.length -= h), t.length))
            break e;
          t.length = 0, t.mode = Ut;
        /* falls through */
        case Ut:
          if (t.flags & 2048) {
            if (f === 0)
              break e;
            h = 0;
            do
              b = a[l + h++], t.head && b && t.length < 65536 && (t.head.name += String.fromCharCode(b));
            while (b && h < f);
            if (t.flags & 512 && (t.check = I(t.check, a, h, l)), f -= h, l += h, b)
              break e;
          } else t.head && (t.head.name = null);
          t.length = 0, t.mode = Ct;
        /* falls through */
        case Ct:
          if (t.flags & 4096) {
            if (f === 0)
              break e;
            h = 0;
            do
              b = a[l + h++], t.head && b && t.length < 65536 && (t.head.comment += String.fromCharCode(b));
            while (b && h < f);
            if (t.flags & 512 && (t.check = I(t.check, a, h, l)), f -= h, l += h, b)
              break e;
          } else t.head && (t.head.comment = null);
          t.mode = Ft;
        /* falls through */
        case Ft:
          if (t.flags & 512) {
            for (; _ < 16; ) {
              if (f === 0)
                break e;
              f--, r += a[l++] << _, _ += 8;
            }
            if (r !== (t.check & 65535)) {
              e.msg = "header crc mismatch", t.mode = m;
              break;
            }
            r = 0, _ = 0;
          }
          t.head && (t.head.hcrc = t.flags >> 9 & 1, t.head.done = !0), e.adler = t.check = 0, t.mode = H;
          break;
        case Mt:
          for (; _ < 32; ) {
            if (f === 0)
              break e;
            f--, r += a[l++] << _, _ += 8;
          }
          e.adler = t.check = Qt(r), r = 0, _ = 0, t.mode = $e;
        /* falls through */
        case $e:
          if (t.havedict === 0)
            return e.next_out = o, e.avail_out = c, e.next_in = l, e.avail_in = f, t.hold = r, t.bits = _, Da;
          e.adler = t.check = 1, t.mode = H;
        /* falls through */
        case H:
          if (i === ma || i === Ze)
            break e;
        /* falls through */
        case et:
          if (t.last) {
            r >>>= _ & 7, _ -= _ & 7, t.mode = it;
            break;
          }
          for (; _ < 3; ) {
            if (f === 0)
              break e;
            f--, r += a[l++] << _, _ += 8;
          }
          switch (t.last = r & 1, r >>>= 1, _ -= 1, r & 3) {
            case 0:
              t.mode = $t;
              break;
            case 1:
              if (Ma(t), t.mode = Ie, i === Ze) {
                r >>>= 2, _ -= 2;
                break e;
              }
              break;
            case 2:
              t.mode = Bt;
              break;
            case 3:
              e.msg = "invalid block type", t.mode = m;
          }
          r >>>= 2, _ -= 2;
          break;
        case $t:
          for (r >>>= _ & 7, _ -= _ & 7; _ < 32; ) {
            if (f === 0)
              break e;
            f--, r += a[l++] << _, _ += 8;
          }
          if ((r & 65535) !== (r >>> 16 ^ 65535)) {
            e.msg = "invalid stored block lengths", t.mode = m;
            break;
          }
          if (t.length = r & 65535, r = 0, _ = 0, t.mode = tt, i === Ze)
            break e;
        /* falls through */
        case tt:
          t.mode = Ht;
        /* falls through */
        case Ht:
          if (h = t.length, h) {
            if (h > f && (h = f), h > c && (h = c), h === 0)
              break e;
            n.set(a.subarray(l, l + h), o), f -= h, l += h, c -= h, o += h, t.length -= h;
            break;
          }
          t.mode = H;
          break;
        case Bt:
          for (; _ < 14; ) {
            if (f === 0)
              break e;
            f--, r += a[l++] << _, _ += 8;
          }
          if (t.nlen = (r & 31) + 257, r >>>= 5, _ -= 5, t.ndist = (r & 31) + 1, r >>>= 5, _ -= 5, t.ncode = (r & 15) + 4, r >>>= 4, _ -= 4, t.nlen > 286 || t.ndist > 30) {
            e.msg = "too many length or distance symbols", t.mode = m;
            break;
          }
          t.have = 0, t.mode = Kt;
        /* falls through */
        case Kt:
          for (; t.have < t.ncode; ) {
            for (; _ < 3; ) {
              if (f === 0)
                break e;
              f--, r += a[l++] << _, _ += 8;
            }
            t.lens[J[t.have++]] = r & 7, r >>>= 3, _ -= 3;
          }
          for (; t.have < 19; )
            t.lens[J[t.have++]] = 0;
          if (t.lencode = t.lendyn, t.lenbits = 7, g = { bits: t.lenbits }, T = be(Ta, t.lens, 0, 19, t.lencode, 0, t.work, g), t.lenbits = g.bits, T) {
            e.msg = "invalid code lengths set", t.mode = m;
            break;
          }
          t.have = 0, t.mode = Xt;
        /* falls through */
        case Xt:
          for (; t.have < t.nlen + t.ndist; ) {
            for (; v = t.lencode[r & (1 << t.lenbits) - 1], w = v >>> 24, S = v >>> 16 & 255, x = v & 65535, !(w <= _); ) {
              if (f === 0)
                break e;
              f--, r += a[l++] << _, _ += 8;
            }
            if (x < 16)
              r >>>= w, _ -= w, t.lens[t.have++] = x;
            else {
              if (x === 16) {
                for (p = w + 2; _ < p; ) {
                  if (f === 0)
                    break e;
                  f--, r += a[l++] << _, _ += 8;
                }
                if (r >>>= w, _ -= w, t.have === 0) {
                  e.msg = "invalid bit length repeat", t.mode = m;
                  break;
                }
                b = t.lens[t.have - 1], h = 3 + (r & 3), r >>>= 2, _ -= 2;
              } else if (x === 17) {
                for (p = w + 3; _ < p; ) {
                  if (f === 0)
                    break e;
                  f--, r += a[l++] << _, _ += 8;
                }
                r >>>= w, _ -= w, b = 0, h = 3 + (r & 7), r >>>= 3, _ -= 3;
              } else {
                for (p = w + 7; _ < p; ) {
                  if (f === 0)
                    break e;
                  f--, r += a[l++] << _, _ += 8;
                }
                r >>>= w, _ -= w, b = 0, h = 11 + (r & 127), r >>>= 7, _ -= 7;
              }
              if (t.have + h > t.nlen + t.ndist) {
                e.msg = "invalid bit length repeat", t.mode = m;
                break;
              }
              for (; h--; )
                t.lens[t.have++] = b;
            }
          }
          if (t.mode === m)
            break;
          if (t.lens[256] === 0) {
            e.msg = "invalid code -- missing end-of-block", t.mode = m;
            break;
          }
          if (t.lenbits = 9, g = { bits: t.lenbits }, T = be(yi, t.lens, 0, t.nlen, t.lencode, 0, t.work, g), t.lenbits = g.bits, T) {
            e.msg = "invalid literal/lengths set", t.mode = m;
            break;
          }
          if (t.distbits = 6, t.distcode = t.distdyn, g = { bits: t.distbits }, T = be(Ai, t.lens, t.nlen, t.ndist, t.distcode, 0, t.work, g), t.distbits = g.bits, T) {
            e.msg = "invalid distances set", t.mode = m;
            break;
          }
          if (t.mode = Ie, i === Ze)
            break e;
        /* falls through */
        case Ie:
          t.mode = Ne;
        /* falls through */
        case Ne:
          if (f >= 6 && c >= 258) {
            e.next_out = o, e.avail_out = c, e.next_in = l, e.avail_in = f, t.hold = r, t.bits = _, va(e, s), o = e.next_out, n = e.output, c = e.avail_out, l = e.next_in, a = e.input, f = e.avail_in, r = t.hold, _ = t.bits, t.mode === H && (t.back = -1);
            break;
          }
          for (t.back = 0; v = t.lencode[r & (1 << t.lenbits) - 1], w = v >>> 24, S = v >>> 16 & 255, x = v & 65535, !(w <= _); ) {
            if (f === 0)
              break e;
            f--, r += a[l++] << _, _ += 8;
          }
          if (S && (S & 240) === 0) {
            for (d = w, A = S, Z = x; v = t.lencode[Z + ((r & (1 << d + A) - 1) >> d)], w = v >>> 24, S = v >>> 16 & 255, x = v & 65535, !(d + w <= _); ) {
              if (f === 0)
                break e;
              f--, r += a[l++] << _, _ += 8;
            }
            r >>>= d, _ -= d, t.back += d;
          }
          if (r >>>= w, _ -= w, t.back += w, t.length = x, S === 0) {
            t.mode = Wt;
            break;
          }
          if (S & 32) {
            t.back = -1, t.mode = H;
            break;
          }
          if (S & 64) {
            e.msg = "invalid literal/length code", t.mode = m;
            break;
          }
          t.extra = S & 15, t.mode = Pt;
        /* falls through */
        case Pt:
          if (t.extra) {
            for (p = t.extra; _ < p; ) {
              if (f === 0)
                break e;
              f--, r += a[l++] << _, _ += 8;
            }
            t.length += r & (1 << t.extra) - 1, r >>>= t.extra, _ -= t.extra, t.back += t.extra;
          }
          t.was = t.length, t.mode = Yt;
        /* falls through */
        case Yt:
          for (; v = t.distcode[r & (1 << t.distbits) - 1], w = v >>> 24, S = v >>> 16 & 255, x = v & 65535, !(w <= _); ) {
            if (f === 0)
              break e;
            f--, r += a[l++] << _, _ += 8;
          }
          if ((S & 240) === 0) {
            for (d = w, A = S, Z = x; v = t.distcode[Z + ((r & (1 << d + A) - 1) >> d)], w = v >>> 24, S = v >>> 16 & 255, x = v & 65535, !(d + w <= _); ) {
              if (f === 0)
                break e;
              f--, r += a[l++] << _, _ += 8;
            }
            r >>>= d, _ -= d, t.back += d;
          }
          if (r >>>= w, _ -= w, t.back += w, S & 64) {
            e.msg = "invalid distance code", t.mode = m;
            break;
          }
          t.offset = x, t.extra = S & 15, t.mode = Gt;
        /* falls through */
        case Gt:
          if (t.extra) {
            for (p = t.extra; _ < p; ) {
              if (f === 0)
                break e;
              f--, r += a[l++] << _, _ += 8;
            }
            t.offset += r & (1 << t.extra) - 1, r >>>= t.extra, _ -= t.extra, t.back += t.extra;
          }
          if (t.offset > t.dmax) {
            e.msg = "invalid distance too far back", t.mode = m;
            break;
          }
          t.mode = jt;
        /* falls through */
        case jt:
          if (c === 0)
            break e;
          if (h = s - c, t.offset > h) {
            if (h = t.offset - h, h > t.whave && t.sane) {
              e.msg = "invalid distance too far back", t.mode = m;
              break;
            }
            h > t.wnext ? (h -= t.wnext, u = t.wsize - h) : u = t.wnext - h, h > t.length && (h = t.length), R = t.window;
          } else
            R = n, u = o - t.offset, h = t.length;
          h > c && (h = c), c -= h, t.length -= h;
          do
            n[o++] = R[u++];
          while (--h);
          t.length === 0 && (t.mode = Ne);
          break;
        case Wt:
          if (c === 0)
            break e;
          n[o++] = t.length, c--, t.mode = Ne;
          break;
        case it:
          if (t.wrap) {
            for (; _ < 32; ) {
              if (f === 0)
                break e;
              f--, r |= a[l++] << _, _ += 8;
            }
            if (s -= c, e.total_out += s, t.total += s, s && (e.adler = t.check = /*UPDATE(state.check, put - _out, _out);*/
            t.flags ? I(t.check, n, s, o - s) : ke(t.check, n, s, o - s)), s = c, (t.flags ? r : Qt(r)) !== t.check) {
              e.msg = "incorrect data check", t.mode = m;
              break;
            }
            r = 0, _ = 0;
          }
          t.mode = Vt;
        /* falls through */
        case Vt:
          if (t.wrap && t.flags) {
            for (; _ < 32; ) {
              if (f === 0)
                break e;
              f--, r += a[l++] << _, _ += 8;
            }
            if (r !== (t.total & 4294967295)) {
              e.msg = "incorrect length check", t.mode = m;
              break;
            }
            r = 0, _ = 0;
          }
          t.mode = Jt;
        /* falls through */
        case Jt:
          T = Ra;
          break e;
        case m:
          T = Si;
          break e;
        case mi:
          return zi;
        case Ia:
        /* falls through */
        default:
          return U;
      }
  return e.next_out = o, e.avail_out = c, e.next_in = l, e.avail_in = f, t.hold = r, t.bits = _, (t.wsize || s !== e.avail_out && t.mode < m && (t.mode < it || i !== Rt)) && Ni(e, e.output, e.next_out, s - e.avail_out), E -= e.avail_in, s -= e.avail_out, e.total_in += E, e.total_out += s, t.total += s, t.wrap && s && (e.adler = t.check = /*UPDATE(state.check, strm.next_out - _out, _out);*/
  t.flags ? I(t.check, n, s, e.next_out - s) : ke(t.check, n, s, e.next_out - s)), e.data_type = t.bits + (t.last ? 64 : 0) + (t.mode === H ? 128 : 0) + (t.mode === Ie || t.mode === tt ? 256 : 0), (E === 0 && s === 0 || i === Rt) && T === ne && (T = Za), T;
}, Ha = (e) => {
  if (!e || !e.state)
    return U;
  let i = e.state;
  return i.window && (i.window = null), e.state = null, ne;
}, Ba = (e, i) => {
  if (!e || !e.state)
    return U;
  const t = e.state;
  return (t.wrap & 2) === 0 ? U : (t.head = i, i.done = !1, ne);
}, Ka = (e, i) => {
  const t = i.length;
  let a, n, l;
  return !e || !e.state || (a = e.state, a.wrap !== 0 && a.mode !== $e) ? U : a.mode === $e && (n = 1, n = ke(n, i, t, 0), n !== a.check) ? Si : (l = Ni(e, i, t, t), l ? (a.mode = mi, zi) : (a.havedict = 1, ne));
};
var Xa = Di, Pa = Zi, Ya = Ri, Ga = Fa, ja = Ii, Wa = $a, Va = Ha, Ja = Ba, Qa = Ka, qa = "pako inflate (from Nodeca project)", K = {
  inflateReset: Xa,
  inflateReset2: Pa,
  inflateResetKeep: Ya,
  inflateInit: Ga,
  inflateInit2: ja,
  inflate: Wa,
  inflateEnd: Va,
  inflateGetHeader: Ja,
  inflateSetDictionary: Qa,
  inflateInfo: qa
};
function el() {
  this.text = 0, this.time = 0, this.xflags = 0, this.os = 0, this.extra = null, this.extra_len = 0, this.name = "", this.comment = "", this.hcrc = 0, this.done = !1;
}
var tl = el;
const Oi = Object.prototype.toString, {
  Z_NO_FLUSH: il,
  Z_FINISH: nl,
  Z_OK: ye,
  Z_STREAM_END: lt,
  Z_NEED_DICT: rt,
  Z_STREAM_ERROR: al,
  Z_DATA_ERROR: ei,
  Z_MEM_ERROR: ll
} = He;
function Ye(e) {
  this.options = Xe.assign({
    chunkSize: 1024 * 64,
    windowBits: 15,
    to: ""
  }, e || {});
  const i = this.options;
  i.raw && i.windowBits >= 0 && i.windowBits < 16 && (i.windowBits = -i.windowBits, i.windowBits === 0 && (i.windowBits = -15)), i.windowBits >= 0 && i.windowBits < 16 && !(e && e.windowBits) && (i.windowBits += 32), i.windowBits > 15 && i.windowBits < 48 && (i.windowBits & 15) === 0 && (i.windowBits |= 15), this.err = 0, this.msg = "", this.ended = !1, this.chunks = [], this.strm = new vi(), this.strm.avail_out = 0;
  let t = K.inflateInit2(
    this.strm,
    i.windowBits
  );
  if (t !== ye)
    throw new Error(ee[t]);
  if (this.header = new tl(), K.inflateGetHeader(this.strm, this.header), i.dictionary && (typeof i.dictionary == "string" ? i.dictionary = Ee.string2buf(i.dictionary) : Oi.call(i.dictionary) === "[object ArrayBuffer]" && (i.dictionary = new Uint8Array(i.dictionary)), i.raw && (t = K.inflateSetDictionary(this.strm, i.dictionary), t !== ye)))
    throw new Error(ee[t]);
}
Ye.prototype.push = function(e, i) {
  const t = this.strm, a = this.options.chunkSize, n = this.options.dictionary;
  let l, o, f;
  if (this.ended) return !1;
  for (i === ~~i ? o = i : o = i === !0 ? nl : il, Oi.call(e) === "[object ArrayBuffer]" ? t.input = new Uint8Array(e) : t.input = e, t.next_in = 0, t.avail_in = t.input.length; ; ) {
    for (t.avail_out === 0 && (t.output = new Uint8Array(a), t.next_out = 0, t.avail_out = a), l = K.inflate(t, o), l === rt && n && (l = K.inflateSetDictionary(t, n), l === ye ? l = K.inflate(t, o) : l === ei && (l = rt)); t.avail_in > 0 && l === lt && t.state.wrap > 0 && e[t.next_in] !== 0; )
      K.inflateReset(t), l = K.inflate(t, o);
    switch (l) {
      case al:
      case ei:
      case rt:
      case ll:
        return this.onEnd(l), this.ended = !0, !1;
    }
    if (f = t.avail_out, t.next_out && (t.avail_out === 0 || l === lt))
      if (this.options.to === "string") {
        let c = Ee.utf8border(t.output, t.next_out), r = t.next_out - c, _ = Ee.buf2string(t.output, c);
        t.next_out = r, t.avail_out = a - r, r && t.output.set(t.output.subarray(c, c + r), 0), this.onData(_);
      } else
        this.onData(t.output.length === t.next_out ? t.output : t.output.subarray(0, t.next_out));
    if (!(l === ye && f === 0)) {
      if (l === lt)
        return l = K.inflateEnd(this.strm), this.onEnd(l), this.ended = !0, !0;
      if (t.avail_in === 0) break;
    }
  }
  return !0;
};
Ye.prototype.onData = function(e) {
  this.chunks.push(e);
};
Ye.prototype.onEnd = function(e) {
  e === ye && (this.options.to === "string" ? this.result = this.chunks.join("") : this.result = Xe.flattenChunks(this.chunks)), this.chunks = [], this.err = e, this.msg = this.strm.msg;
};
function rl(e, i) {
  const t = new Ye(i);
  if (t.push(e), t.err) throw t.msg || ee[t.err];
  return t.result;
}
var fl = rl, ol = {
  inflate: fl
};
const { deflate: _l } = xa, { inflate: hl } = ol;
var dl = _l, sl = hl;
export {
  dl as d,
  sl as i
};
