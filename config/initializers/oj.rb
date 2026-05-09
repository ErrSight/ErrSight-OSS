# Configure Oj as the default JSON parser for speed
Oj.optimize_rails
Oj.default_options = {
  mode: :compat,
  symbol_keys: false,
  bigdecimal_as_decimal: true
}
