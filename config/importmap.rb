# Pin npm packages by running ./bin/importmap

pin "application"
pin "screw_3d", to: "screw_3d.js"
pin "three", to: "https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.module.js"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "cep_mask", to: "cep_mask.js"
pin_all_from "app/javascript/controllers", under: "controllers"
