# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [v00.00.14] - 2022-07-15

## Fixed
- Added styling of payment results page

## [v00.00.13] - 2022-07-15

## Fixed
- Added a missing import

## [v00.00.12] - 2022-07-14

## Fixed
- Update plugin to work with Koha 21.11

## [v00.00.11] - 2020-06-19

### Fixed
- Update plugin to work with Koha 19.11 and 20.05 releases.

## [v00.00.10] - 2020-06-18

### Changed
- Updated configuration page styling to match modern practive
- Added the `interface` argument to the parameters passed in the call to Koha::Account::pay

## [v00.00.09] - 2019-07-05

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

