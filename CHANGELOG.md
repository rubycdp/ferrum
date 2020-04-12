## [0.1.1] - (Aug 26, 2019) ##

### Added

- stringify the `url` which passed to `Ferrum::Page#goto`

## [0.1.0] - (Aug 26, 2019) ##

### Added

- fires the `Ferrum::NodeError` on zero of node_id

### Changed

- basic description in README 

## [0.1.0.alpha] - (Aug 2, 2019) ##

### Added

- Initial implementation

    #### Modules:

    - Ferrum

    - Ferrum::Network - simple requests/responses data store

    #### Classes:

    - Ferrum::Browser - basic command interface

    - Ferrum::Cookie - simple store of the cookie attributes

    - Ferrum::Node - abstract level of DOM-node with basic methods

    - Ferrum::Page - basic object of the command references, which included DOM, network and browser logic

    - Ferrum::Targets - initialize of the `window` manager with a clean browser state

    - classes of errors with a description of specific raises reasons

[0.1.1]: https://github.com/rubycdp/ferrum/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/rubycdp/ferrum/compare/v0.1.0.alpha...v0.1.0
[0.1.0.alpha]: https://github.com/rubycdp/ferrum/releases/tag/v0.1.0.alpha
