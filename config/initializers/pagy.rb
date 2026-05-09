require "pagy/extras/overflow"
require "pagy/extras/metadata"
require "pagy/extras/array"

Pagy::DEFAULT[:items] = 25
Pagy::DEFAULT[:overflow] = :last_page
