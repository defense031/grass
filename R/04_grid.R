# 04_grid.R — Parameter grid construction
#
# Builds the full factorial grid (495 scenarios) from config.yaml
# and pre-computes ground-truth columns for each scenario.

build_parameter_grid <- function(config) {
  # Extract profile Se/Sp values into a data.frame
  profiles <- do.call(rbind, lapply(names(config$rater_profiles), function(pname) {
    p <- config$rater_profiles[[pname]]
    data.frame(
      profile_name = pname,
      Se1 = p$Se1, Sp1 = p$Sp1,
      Se2 = p$Se2, Sp2 = p$Sp2,
      stringsAsFactors = FALSE
    )
  }))

  # Full factorial: prevalence x sample_size x profile
  grid <- expand.grid(
    prevalence   = config$prevalences,
    N            = config$sample_sizes,
    profile_name = profiles$profile_name,
    stringsAsFactors = FALSE
  )

  # Join Se/Sp values
  grid <- merge(grid, profiles, by = "profile_name", sort = FALSE)

  # Add scenario ID
  grid$scenario_id <- seq_len(nrow(grid))

  # Determine n_reps: stress conditions get more reps
  stress_prev <- config$stress_conditions$prevalences
  stress_n    <- config$stress_conditions$sample_sizes
  grid$n_reps <- ifelse(
    grid$prevalence %in% stress_prev & grid$N %in% stress_n,
    config$n_reps_stress,
    config$n_reps
  )

  # Pre-compute ground truth for each scenario
  gt_list <- mapply(
    compute_ground_truth,
    Se1 = grid$Se1, Sp1 = grid$Sp1,
    Se2 = grid$Se2, Sp2 = grid$Sp2,
    prevalence = grid$prevalence,
    MoreArgs = list(cost_ratios = config$cost_ratios),
    SIMPLIFY = FALSE
  )
  gt_df <- do.call(rbind, gt_list)

  # Bind ground truth columns to grid
  grid <- cbind(grid, gt_df)

  # Reorder columns for readability
  front_cols <- c("scenario_id", "profile_name", "prevalence", "N",
                  "Se1", "Sp1", "Se2", "Sp2", "n_reps")
  other_cols <- setdiff(names(grid), front_cols)
  grid <- grid[, c(front_cols, other_cols)]

  grid
}
