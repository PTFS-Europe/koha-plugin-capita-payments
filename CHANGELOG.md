# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Ability to define a fundCode to be added globally to item payments

## [v00.00.08] - 2019-06-17

### Fixed
- Corrections to override of the client endpoint via the Pay360Portal preference.

## [v00.00.07] - 2019-06-14

### Fixed
- Allow override of the client endpoint via the Pay360Portal preference.

## [v00.00.06] - 2019-06-14

### Fixed
- Make Koha::Patrons->find call explicitly use userid.

## [v00.00.05] - 2019-04-12

### Fixed
- Respect renewal rules when renewal incrementing fines.

## [v00.00.04] - 2018-12-06

### Fixed
- Compilation error for resultset name typo.

## [v00.00.03] - 2018-12-06

### Added
- Add user email address to data in invokeRequest.

### Changed
- Remove `minlegth` from being appended to itemSummary/description fields.
- Use correct currency in opac end process.

